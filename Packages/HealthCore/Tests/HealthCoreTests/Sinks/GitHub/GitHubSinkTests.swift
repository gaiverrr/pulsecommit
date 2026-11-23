import XCTest
@testable import HealthCore

final class GitHubSinkTests: XCTestCase {
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

    func testHappyPathDeliversAtomicCommit() async throws {
        let parentSha = "parent_sha_abc"
        let parentTreeSha = "parent_tree_sha_999"
        let blobSha = "blob_sha_xyz"
        let treeSha = "tree_sha_123"
        let commitSha = "commit_sha_456"
        let commitHTMLURL = "https://github.com/alice/health/commit/\(commitSha)"

        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": parentSha, "type": "commit", "url": "https://api.github.com/repos/alice/health/git/commits/\(parentSha)"]
            ])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/\(parentSha)",
            response: .json([
                "sha": parentSha,
                "tree": ["sha": parentTreeSha, "url": "https://api.github.com/repos/alice/health/git/trees/\(parentTreeSha)"]
            ])
        )
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
                "sha": commitSha,
                "url": "https://api.github.com/repos/alice/health/git/commits/\(commitSha)",
                "html_url": commitHTMLURL
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": commitSha, "type": "commit", "url": "https://api.github.com/repos/alice/health/git/commits/\(commitSha)"]
            ])
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        let snapshot = makeSnapshot()
        let files = [
            FileEntry(path: "2026-05-14/summary.json", data: Data("{\"a\":1}".utf8)),
            FileEntry(path: "2026-05-14/summary.md", data: Data("# hi".utf8))
        ]

        let result = try await sink.deliver(snapshot: snapshot, files: files)

        XCTAssertEqual(result, .success(reference: commitSha, url: URL(string: commitHTMLURL)))

        let captured = GitHubMockTransport.captured
        XCTAssertEqual(captured.count, 7)
        XCTAssertEqual(captured[0].httpMethod, "GET")
        XCTAssertTrue(captured[0].url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)

        XCTAssertEqual(captured[1].httpMethod, "GET")
        XCTAssertTrue(captured[1].url?.absoluteString.hasSuffix("/git/commits/\(parentSha)") ?? false)

        XCTAssertEqual(captured[2].httpMethod, "POST")
        XCTAssertTrue(captured[2].url?.absoluteString.hasSuffix("/git/blobs") ?? false)
        XCTAssertEqual(captured[3].httpMethod, "POST")
        XCTAssertTrue(captured[3].url?.absoluteString.hasSuffix("/git/blobs") ?? false)

        XCTAssertEqual(captured[4].httpMethod, "POST")
        XCTAssertTrue(captured[4].url?.absoluteString.hasSuffix("/git/trees") ?? false)
        let treeBody = try XCTUnwrap(captured[4].httpBody)
        let treeReq = try JSONDecoder().decode(GitHubCreateTreeRequest.self, from: treeBody)
        XCTAssertEqual(treeReq.baseTree, parentTreeSha)
        XCTAssertEqual(treeReq.tree.map(\.path), ["2026-05-14/summary.json", "2026-05-14/summary.md"])
        XCTAssertTrue(treeReq.tree.allSatisfy { $0.sha == blobSha && $0.mode == "100644" && $0.type == "blob" })

        XCTAssertEqual(captured[5].httpMethod, "POST")
        XCTAssertTrue(captured[5].url?.absoluteString.hasSuffix("/git/commits") ?? false)
        let commitBody = try XCTUnwrap(captured[5].httpBody)
        let commitReq = try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: commitBody)
        XCTAssertEqual(commitReq.tree, treeSha)
        XCTAssertEqual(commitReq.parents, [parentSha])
        XCTAssertTrue(commitReq.message.contains("2026-05-14"))
        XCTAssertTrue(commitReq.message.contains("12483 steps"))
        XCTAssertTrue(commitReq.message.contains("1 workout"))

        XCTAssertEqual(captured[6].httpMethod, "PATCH")
        XCTAssertTrue(captured[6].url?.absoluteString.hasSuffix("/git/refs/heads/main") ?? false)
        let patchBody = try XCTUnwrap(captured[6].httpBody)
        let patchReq = try JSONDecoder().decode(GitHubUpdateRefRequest.self, from: patchBody)
        XCTAssertEqual(patchReq.sha, commitSha)
    }

    func testSubdirIsAppliedToFilePaths() async throws {
        let credsWithSubdir = StaticCredentialProvider(
            token: "ghp_test",
            owner: "alice",
            repo: "health",
            branch: "main",
            subdir: "pulse"
        )

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
            response: .json(["sha": "c", "url": "u", "html_url": "https://github.com/alice/health/commit/c"], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": "c", "type": "commit", "url": "u"]
            ])
        )

        let sink = GitHubSink(credentialProvider: credsWithSubdir, session: .shared)
        _ = try await sink.deliver(
            snapshot: makeSnapshot(),
            files: [FileEntry(path: "2026-05-14/summary.json", data: Data("x".utf8))]
        )

        let treeRequest = try XCTUnwrap(GitHubMockTransport.captured.first { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/trees") ?? false) })
        let body = try XCTUnwrap(treeRequest.httpBody)
        let req = try JSONDecoder().decode(GitHubCreateTreeRequest.self, from: body)
        XCTAssertEqual(req.tree.first?.path, "pulse/2026-05-14/summary.json")
    }

    func testRefConflictTriggersSingleRetry() async throws {
        let parentSha1 = "parent_sha_1"
        let parentSha2 = "parent_sha_2"
        let blobSha = "blob_sha"
        let treeSha1 = "tree_1"
        let treeSha2 = "tree_2"
        let commitSha1 = "commit_1"
        let commitSha2 = "commit_2"
        let finalHTMLURL = "https://github.com/alice/health/commit/\(commitSha2)"

        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: [
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": parentSha1, "type": "commit", "url": "u"]
                ]),
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": parentSha2, "type": "commit", "url": "u"]
                ])
            ]
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/\(parentSha1)",
            response: .json([
                "sha": parentSha1,
                "tree": ["sha": "pt1", "url": "u"]
            ])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/\(parentSha2)",
            response: .json([
                "sha": parentSha2,
                "tree": ["sha": "pt2", "url": "u"]
            ])
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json(["sha": blobSha, "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/trees",
            responses: [
                .json(["sha": treeSha1, "url": "u"], statusCode: 201),
                .json(["sha": treeSha2, "url": "u"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/commits",
            responses: [
                .json([
                    "sha": commitSha1,
                    "url": "u",
                    "html_url": "https://github.com/alice/health/commit/\(commitSha1)"
                ], statusCode: 201),
                .json([
                    "sha": commitSha2,
                    "url": "u",
                    "html_url": finalHTMLURL
                ], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            responses: [
                .json(["message": "Update is not a fast forward"], statusCode: 422),
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": commitSha2, "type": "commit", "url": "u"]
                ])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        let files = [FileEntry(path: "2026-05-14/summary.json", data: Data("{}".utf8))]

        let result = try await sink.deliver(snapshot: makeSnapshot(), files: files)

        XCTAssertEqual(result, .success(reference: commitSha2, url: URL(string: finalHTMLURL)))

        let captured = GitHubMockTransport.captured
        let methods = captured.map { ($0.httpMethod ?? "") + " " + ($0.url?.path ?? "") }
        let getRefCount = methods.filter { $0.hasPrefix("GET") && $0.hasSuffix("/git/ref/heads/main") }.count
        let treeCount = methods.filter { $0.hasPrefix("POST") && $0.hasSuffix("/git/trees") }.count
        let commitCount = methods.filter { $0.hasPrefix("POST") && $0.hasSuffix("/git/commits") }.count
        let patchCount = methods.filter { $0.hasPrefix("PATCH") && $0.hasSuffix("/git/refs/heads/main") }.count
        XCTAssertEqual(getRefCount, 2)
        XCTAssertEqual(treeCount, 2)
        XCTAssertEqual(commitCount, 2)
        XCTAssertEqual(patchCount, 2)

        let commitBodies = captured
            .filter { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }
            .compactMap { $0.httpBody }
        XCTAssertEqual(commitBodies.count, 2)
        let commitReqs = try commitBodies.map { try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: $0) }
        XCTAssertEqual(commitReqs[0].parents, [parentSha1])
        XCTAssertEqual(commitReqs[1].parents, [parentSha2])
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
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count"),
            "sleep": SummaryFragment(metrics: ["duration_minutes": .int(437)])
        ]
        snap.workouts = [
            WorkoutDTO(
                id: "7f3a",
                type: .outdoorRun,
                startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
                endDate: SampleFixtures.iso("2026-05-14T07:38:00Z"),
                durationMinutes: 38,
                distanceKm: 6.2,
                activeEnergyKcal: 410,
                avgHeartRate: 152,
                maxHeartRate: 174,
                route: []
            )
        ]
        return snap
    }
}
