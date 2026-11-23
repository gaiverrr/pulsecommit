import XCTest
@testable import HealthCore

final class GitHubSinkEmptyRepoTests: XCTestCase {
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

    // Regression: the Git Data API (POST /git/blobs, /git/trees, /git/commits) cannot
    // bootstrap a brand-new empty repository; every call returns
    // 409 "Git Repository is empty." until at least one commit exists. The only
    // endpoint that can create the first commit is the Contents API
    // (PUT /repos/{owner}/{repo}/contents/{path}). After that bootstrap commit lands,
    // the normal Git Data API path can be used as usual.
    // See: https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents
    func testEmptyRepositoryBootstrapsViaContentsAPIThenCommitsAllFiles() async throws {
        let seedSha = "seed_commit_sha"
        let seedTreeSha = "seed_tree_sha"
        let blobSha = "blob_sha"
        let treeSha = "tree_sha"
        let finalSha = "final_commit_sha"
        let finalHTMLURL = "https://github.com/alice/health/commit/\(finalSha)"

        // 1st call: get-ref returns 404 (empty repo).
        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: [
                .json(["message": "Not Found"], statusCode: 404),
                // 3rd call: after Contents API bootstrap, get-ref returns 200.
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": seedSha, "type": "commit", "url": "u"]
                ], statusCode: 200)
            ]
        )

        // 2nd call: Contents API PUT creates the seed commit.
        GitHubMockTransport.addRoute(
            method: "PUT",
            pathSuffix: "/contents/2026-05-14/summary.md",
            response: .json([
                "content": ["sha": "content_blob_sha", "path": "2026-05-14/summary.md"],
                "commit": [
                    "sha": seedSha,
                    "url": "https://api.github.com/repos/alice/health/git/commits/\(seedSha)",
                    "html_url": "https://github.com/alice/health/commit/\(seedSha)"
                ]
            ], statusCode: 201)
        )

        // 4th call: getCommit on the seed sha returns the seed tree.
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/\(seedSha)",
            response: .json([
                "sha": seedSha,
                "tree": ["sha": seedTreeSha, "url": "u"]
            ], statusCode: 200)
        )

        // Normal happy path.
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json([
                "sha": blobSha,
                "url": "https://api.github.com/repos/alice/health/git/blobs/\(blobSha)"
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/trees",
            response: .json([
                "sha": treeSha,
                "url": "https://api.github.com/repos/alice/health/git/trees/\(treeSha)"
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/commits",
            response: .json([
                "sha": finalSha,
                "url": "https://api.github.com/repos/alice/health/git/commits/\(finalSha)",
                "html_url": finalHTMLURL
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": finalSha, "type": "commit", "url": "u"]
            ], statusCode: 200)
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        let snapshot = makeSnapshot()
        let files = [
            FileEntry(path: "2026-05-14/summary.json", data: Data("{\"a\":1}".utf8)),
            FileEntry(path: "2026-05-14/summary.md", data: Data("# pulse".utf8))
        ]

        let result = try await sink.deliver(snapshot: snapshot, files: files)

        XCTAssertEqual(result, .success(reference: finalSha, url: URL(string: finalHTMLURL)))

        let captured = GitHubMockTransport.captured

        // Sequence must be: GET ref(404) → PUT contents → GET ref(200) → GET commit → blobs → tree → commit → PATCH ref.
        // Crucially, NO POST /git/blobs may happen before the PUT /contents/* call,
        // because the real GitHub API rejects blob creation on an empty repo with 409.
        let putContentsIdx = try XCTUnwrap(captured.firstIndex(where: { req in
            (req.httpMethod ?? "") == "PUT" && (req.url?.path.contains("/contents/") ?? false)
        }), "Expected a PUT /contents/* bootstrap call")
        let firstBlobIdx = captured.firstIndex(where: { req in
            (req.httpMethod ?? "") == "POST" && (req.url?.absoluteString.hasSuffix("/git/blobs") ?? false)
        })
        if let firstBlobIdx {
            XCTAssertGreaterThan(firstBlobIdx, putContentsIdx, "POST /git/blobs must not happen before the Contents API bootstrap")
        }

        // Assert wire shape of the Contents API call.
        let contentsReq = captured[putContentsIdx]
        XCTAssertEqual(contentsReq.httpMethod, "PUT")
        XCTAssertTrue(contentsReq.url?.path.hasSuffix("/contents/2026-05-14/summary.md") ?? false,
                      "Expected the seed file to be summary.md (preferred when present), got \(contentsReq.url?.path ?? "nil")")
        let contentsBody = try XCTUnwrap(contentsReq.httpBody)
        let contentsJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: contentsBody) as? [String: Any])
        XCTAssertEqual(contentsJSON["branch"] as? String, "main")
        XCTAssertEqual(contentsJSON["message"] as? String, "Pulse Commit · initial commit")
        let base64 = try XCTUnwrap(contentsJSON["content"] as? String)
        XCTAssertEqual(base64, Data("# pulse".utf8).base64EncodedString())

        // Final commit on tip must include all files (2 blobs).
        let blobPosts = captured.filter { ($0.httpMethod ?? "") == "POST" && ($0.url?.absoluteString.hasSuffix("/git/blobs") ?? false) }
        XCTAssertEqual(blobPosts.count, 2, "After bootstrap, the normal commit path uploads blobs for every file")

        // Daily-snapshot commit message must not be the seed message.
        let commitPost = try XCTUnwrap(captured.first(where: { ($0.httpMethod ?? "") == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }))
        let commitReq = try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: try XCTUnwrap(commitPost.httpBody))
        XCTAssertEqual(commitReq.parents, [seedSha])
        XCTAssertTrue(commitReq.message.contains("2026-05-14"))
        XCTAssertNotEqual(commitReq.message, "Pulse Commit · initial commit")
    }

    func testEmptyRepository409FromGetRefAlsoTriggersContentsAPIBootstrap() async throws {
        let seedSha = "seed_409"
        let finalSha = "final_409"
        let finalHTMLURL = "https://github.com/alice/health/commit/\(finalSha)"

        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: [
                .json(["message": "Git Repository is empty."], statusCode: 409),
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": seedSha, "type": "commit", "url": "u"]
                ], statusCode: 200)
            ]
        )
        GitHubMockTransport.addRoute(
            method: "PUT",
            pathSuffix: "/contents/2026-05-14/summary.json",
            response: .json([
                "content": ["sha": "c", "path": "2026-05-14/summary.json"],
                "commit": ["sha": seedSha, "url": "u", "html_url": "h"]
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/\(seedSha)",
            response: .json([
                "sha": seedSha,
                "tree": ["sha": "seed_tree", "url": "u"]
            ], statusCode: 200)
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
                "sha": finalSha,
                "url": "u",
                "html_url": finalHTMLURL
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": finalSha, "type": "commit", "url": "u"]
            ], statusCode: 200)
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        // Only one file, no summary.md → seed file falls back to first FileEntry.
        let result = try await sink.deliver(
            snapshot: makeSnapshot(),
            files: [FileEntry(path: "2026-05-14/summary.json", data: Data("{}".utf8))]
        )

        XCTAssertEqual(result, .success(reference: finalSha, url: URL(string: finalHTMLURL)))

        let captured = GitHubMockTransport.captured
        let putContents = captured.filter { ($0.httpMethod ?? "") == "PUT" && ($0.url?.path.contains("/contents/") ?? false) }
        XCTAssertEqual(putContents.count, 1, "Exactly one Contents API call to bootstrap")
        let patchRefs = captured.filter { $0.httpMethod == "PATCH" && ($0.url?.absoluteString.hasSuffix("/git/refs/heads/main") ?? false) }
        XCTAssertEqual(patchRefs.count, 1, "Normal happy path PATCHes the ref after the bootstrap commit")
    }

    private func makeSnapshot() -> DailySnapshot {
        var snap = DailySnapshot(
            date: SampleFixtures.iso("2026-05-14T00:00:00Z"),
            timezone: "UTC",
            generatedAt: SampleFixtures.iso("2026-05-14T22:30:12Z"),
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = [
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count")
        ]
        snap.workouts = []
        return snap
    }
}
