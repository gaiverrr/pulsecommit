import XCTest
@testable import HealthCore

// Regression: when the branch tip moves under us mid-commit (e.g. another
// process or the bootstrap-then-commit sequence on a brand-new repo), GitHub
// returns 422 "Update is not a fast forward" on PATCH /git/refs. The sink must
// re-fetch the ref and rebuild the commit chain, **up to three times** before
// giving up. The previous implementation only retried once, so users who hit
// two consecutive 422s (observed in the field on second-commit-same-day after
// the Contents API bootstrap commit had warmed the ref cache) saw a hard fail.
final class GitHubSinkRetryTests: XCTestCase {
    private let credentialProvider = StaticCredentialProvider(
        token: "ghp_test",
        owner: "alice",
        repo: "health",
        branch: "main"
    )

    override func setUp() {
        super.setUp()
        GitHubMockTransport.register()
    }

    override func tearDown() {
        GitHubMockTransport.unregister()
        super.tearDown()
    }

    func testCommitRetriesUpTo3TimesOnNonFastForward() async throws {
        // 3 PATCH attempts: 422, 422, 200.
        // Expect: 3 full commit cycles (getRef + getCommit + blob + tree + commit + PATCH).

        let parents = ["p1", "p2", "p3"]
        let parentTrees = ["pt1", "pt2", "pt3"]
        let commits = ["c1", "c2", "c3"]
        let trees = ["t1", "t2", "t3"]
        let finalHTMLURL = "https://github.com/alice/health/commit/\(commits[2])"

        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: parents.map { sha in
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": sha, "type": "commit", "url": "u"]
                ])
            }
        )
        for (parent, parentTree) in zip(parents, parentTrees) {
            GitHubMockTransport.addRoute(
                method: "GET",
                pathSuffix: "/git/commits/\(parent)",
                response: .json([
                    "sha": parent,
                    "tree": ["sha": parentTree, "url": "u"]
                ])
            )
        }
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json(["sha": "b", "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/trees",
            responses: trees.map { .json(["sha": $0, "url": "u"], statusCode: 201) }
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/commits",
            responses: commits.map {
                .json([
                    "sha": $0,
                    "url": "u",
                    "html_url": "https://github.com/alice/health/commit/\($0)"
                ], statusCode: 201)
            }
        )
        GitHubMockTransport.addRouteSequence(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            responses: [
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": commits[2], "type": "commit", "url": "u"]
                ])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        let result = try await sink.deliver(
            snapshot: makeSnapshot(),
            files: [FileEntry(path: "2026-05-16/summary.json", data: Data("{}".utf8))]
        )

        XCTAssertEqual(result, .success(reference: commits[2], url: URL(string: finalHTMLURL)))

        let captured = GitHubMockTransport.captured
        let methods = captured.map { ($0.httpMethod ?? "") + " " + ($0.url?.path ?? "") }
        let getRefCount = methods.filter { $0.hasPrefix("GET") && $0.hasSuffix("/git/ref/heads/main") }.count
        let treeCount = methods.filter { $0.hasPrefix("POST") && $0.hasSuffix("/git/trees") }.count
        let commitCount = methods.filter { $0.hasPrefix("POST") && $0.hasSuffix("/git/commits") }.count
        let patchCount = methods.filter { $0.hasPrefix("PATCH") && $0.hasSuffix("/git/refs/heads/main") }.count
        XCTAssertEqual(getRefCount, 3, "expected 3 getRef cycles (initial + 2 retries)")
        XCTAssertEqual(treeCount, 3)
        XCTAssertEqual(commitCount, 3)
        XCTAssertEqual(patchCount, 3)

        let commitReqs = try captured
            .filter { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }
            .compactMap { $0.httpBody }
            .map { try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: $0) }
        XCTAssertEqual(commitReqs.map { $0.parents }, [["p1"], ["p2"], ["p3"]],
                       "each retry must rebuild against the freshly fetched parent SHA")
    }

    func testCommitGivesUpAfter3NonFastForwardRetries() async throws {
        // PATCH returns 422 forever. Expect a dedicated `.nonFastForwardExhausted`
        // surfaced after the initial attempt + 3 retries (= 4 PATCH attempts).
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": "p", "type": "commit", "url": "u"]
            ])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/p",
            response: .json([
                "sha": "p",
                "tree": ["sha": "pt", "url": "u"]
            ])
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json(["sha": "b", "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/trees",
            response: .json(["sha": "t", "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/commits",
            response: .json([
                "sha": "c", "url": "u", "html_url": "https://github.com/alice/health/commit/c"
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            response: .json(["message": "Update is not a fast forward."], statusCode: 422)
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        do {
            _ = try await sink.deliver(
                snapshot: makeSnapshot(),
                files: [FileEntry(path: "2026-05-16/summary.json", data: Data("{}".utf8))]
            )
            XCTFail("expected nonFastForwardExhausted error")
        } catch GitHubSinkError.nonFastForwardExhausted {
            // expected
        }

        let patchCount = GitHubMockTransport.captured
            .filter { $0.httpMethod == "PATCH" && ($0.url?.absoluteString.hasSuffix("/git/refs/heads/main") ?? false) }
            .count
        XCTAssertEqual(patchCount, 4, "expected initial attempt + 3 retries = 4 PATCH calls")
    }

    private func makeSnapshot() -> DailySnapshot {
        var snap = DailySnapshot(
            date: SampleFixtures.iso("2026-05-16T00:00:00Z"),
            timezone: "UTC",
            generatedAt: SampleFixtures.iso("2026-05-16T22:30:12Z"),
            deviceName: "iPhone 16 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = ["steps": SummaryFragment(metrics: ["total": .int(1000)], unit: "count")]
        return snap
    }
}
