import XCTest
@testable import HealthCore

// Verifies the GitHubSink fires `onAttempt(retryIndex, totalAttempts, reason)`
// on each non-fast-forward retry — not on the initial attempt. With 422 twice
// then success, we expect (1, 4, "non-fast-forward") and (2, 4, "non-fast-forward").
final class GitHubSinkProgressTests: XCTestCase {
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

    func testOnAttemptFiresForEachNonFastForwardRetry() async throws {
        let parents = ["p1", "p2", "p3"]
        let parentTrees = ["pt1", "pt2", "pt3"]
        let commits = ["c1", "c2", "c3"]
        let trees = ["t1", "t2", "t3"]

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

        let recorder = AttemptRecorder()
        let onAttempt: @Sendable (Int, Int, String) async -> Void = { attempt, total, reason in
            recorder.record(attempt: attempt, total: total, reason: reason)
        }

        _ = try await sink.deliver(
            snapshot: makeSnapshot(),
            files: [FileEntry(path: "2026-05-16/summary.json", data: Data("{}".utf8))],
            onAttempt: onAttempt
        )

        let events = recorder.snapshot()
        XCTAssertEqual(events.count, 2, "expected exactly 2 onAttempt calls (one per retry, not the initial attempt)")
        XCTAssertEqual(events.first?.attempt, 1)
        XCTAssertEqual(events.first?.total, 4)
        XCTAssertEqual(events.first?.reason, "non-fast-forward")
        XCTAssertEqual(events.last?.attempt, 2)
        XCTAssertEqual(events.last?.total, 4)
        XCTAssertEqual(events.last?.reason, "non-fast-forward")
    }

    /// Regression for pc-5lm: onAttempt is now an async closure invoked inline
    /// (no orphan Task). A handler that awaits a checkpoint MUST block the
    /// retry — proving the call is structured and that cancellation of the
    /// surrounding task tears down the handler before its body proceeds.
    func testOnAttemptIsAwaitedInline() async throws {
        let parents = ["p1", "p2"]
        let parentTrees = ["pt1", "pt2"]
        let commits = ["c1", "c2"]
        let trees = ["t1", "t2"]

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
                response: .json(["sha": parent, "tree": ["sha": parentTree, "url": "u"]])
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
                .json([
                    "ref": "refs/heads/main",
                    "object": ["sha": commits[1], "type": "commit", "url": "u"]
                ])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        let observer = AsyncObserver()
        _ = try await sink.deliver(
            snapshot: makeSnapshot(),
            files: [FileEntry(path: "2026-05-16/summary.json", data: Data("{}".utf8))],
            onAttempt: { attempt, _, _ in
                await observer.tick(attempt: attempt)
            }
        )
        let observed = await observer.observed
        XCTAssertEqual(observed, [1], "async onAttempt must be awaited inline before the retry proceeds")
    }

    private actor AsyncObserver {
        private(set) var observed: [Int] = []
        func tick(attempt: Int) async {
            observed.append(attempt)
        }
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

private final class AttemptRecorder: @unchecked Sendable {
    struct Event {
        let attempt: Int
        let total: Int
        let reason: String
    }

    private let lock = NSLock()
    private var events: [Event] = []

    func record(attempt: Int, total: Int, reason: String) {
        lock.lock()
        defer { lock.unlock() }
        events.append(Event(attempt: attempt, total: total, reason: reason))
    }

    func snapshot() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}
