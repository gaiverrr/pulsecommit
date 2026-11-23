import XCTest
@testable import HealthCore

// Regression: 7-day backfills failed with HTTP 422 "Update is not a fast
// forward" after the 1s/3s/9s retry backoff. Root cause was that each
// `deliver` call independently fetched the ref via `getRef`, and GitHub's
// edge cache returned a stale tip for many seconds after our previous
// write. The fix caches the SHA we just wrote and uses it as the parent
// for the next `deliver` call. These tests pin the new behavior.
final class GitHubSinkCarryForwardShaTests: XCTestCase {
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

    // MARK: - 1. First deliver still hits getRef exactly once

    func testFirstDeliverCallsGetRef() async throws {
        installHappyPathRoutes(parentSha: "p", parentTreeSha: "pt", commitSha: "c", treeSha: "t", blobSha: "b")

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-10"),
            files: [FileEntry(path: "2026-05-10/summary.json", data: Data("{}".utf8))]
        )

        let getRefCount = GitHubMockTransport.captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)
        }.count
        XCTAssertEqual(getRefCount, 1, "first deliver must discover the current tip via getRef")
    }

    // MARK: - 2. Second deliver in the same session skips getRef entirely

    func testSecondDeliverSkipsGetRef() async throws {
        // Two sequential deliveries on the same sink instance.
        // Day-1 SHA: c1, then day-2 commits against parent = c1 (the cached SHA),
        // producing c2. No second getRef must be made; the cache replaces it.

        // getRef only ever needed once (initial deliver).
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": "c0", "type": "commit", "url": "u"]
            ])
        )
        // getCommit is called once per deliver: first against c0 (the freshly-
        // fetched ref tip), then against c1 (the cached SHA from delivery #1).
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c0",
            response: .json(["sha": "c0", "tree": ["sha": "tree0", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c1",
            response: .json(["sha": "c1", "tree": ["sha": "tree1", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json(["sha": "b", "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/trees",
            responses: [
                .json(["sha": "t1", "url": "u"], statusCode: 201),
                .json(["sha": "t2", "url": "u"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/commits",
            responses: [
                .json(["sha": "c1", "url": "u", "html_url": "https://github.com/alice/health/commit/c1"], statusCode: 201),
                .json(["sha": "c2", "url": "u", "html_url": "https://github.com/alice/health/commit/c2"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            responses: [
                .json(["ref": "refs/heads/main", "object": ["sha": "c1", "type": "commit", "url": "u"]]),
                .json(["ref": "refs/heads/main", "object": ["sha": "c2", "type": "commit", "url": "u"]])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-10"),
            files: [FileEntry(path: "2026-05-10/summary.json", data: Data("{}".utf8))]
        )
        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-11"),
            files: [FileEntry(path: "2026-05-11/summary.json", data: Data("{}".utf8))]
        )

        let captured = GitHubMockTransport.captured
        let getRefCount = captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)
        }.count
        XCTAssertEqual(getRefCount, 1, "second deliver must reuse the cached SHA, not call getRef again")

        // Day-2 commit must have parent = c1 (the cached SHA from day-1), proving
        // that the cache, not getRef, drove the parent selection.
        let commitBodies = captured
            .filter { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }
            .compactMap { $0.httpBody }
        XCTAssertEqual(commitBodies.count, 2)
        let parents = try commitBodies.map { try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: $0).parents }
        XCTAssertEqual(parents, [["c0"], ["c1"]])

        // Day-2 must have read the parent tree via getCommit(c1).
        let getCommitC1Count = captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/commits/c1") ?? false)
        }.count
        XCTAssertEqual(getCommitC1Count, 1, "second deliver must still fetch the parent tree via getCommit(cached)")
    }

    // MARK: - 3. Second deliver: 422 on cached SHA → fall back to getRef and succeed

    func testSecondDeliverWith422FallsBackToGetRef() async throws {
        // Day-1 succeeds with parent=c0 → commit=c1 (cached).
        // Day-2 attempt #1 uses cached c1, but PATCH returns 422 (someone else
        // moved the ref). Retry must drop the cache, call getRef (returns c1real),
        // rebuild, and succeed.

        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: [
                // Day-1 initial getRef.
                .json(["ref": "refs/heads/main", "object": ["sha": "c0", "type": "commit", "url": "u"]]),
                // Day-2 retry getRef after 422 invalidates the cache.
                .json(["ref": "refs/heads/main", "object": ["sha": "c1real", "type": "commit", "url": "u"]])
            ]
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c0",
            response: .json(["sha": "c0", "tree": ["sha": "tree0", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c1",
            response: .json(["sha": "c1", "tree": ["sha": "tree1", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c1real",
            response: .json(["sha": "c1real", "tree": ["sha": "tree1real", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json(["sha": "b", "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/trees",
            responses: [
                .json(["sha": "t1", "url": "u"], statusCode: 201),
                .json(["sha": "t2a", "url": "u"], statusCode: 201),
                .json(["sha": "t2b", "url": "u"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/commits",
            responses: [
                .json(["sha": "c1", "url": "u", "html_url": "https://github.com/alice/health/commit/c1"], statusCode: 201),
                .json(["sha": "c2a", "url": "u", "html_url": "https://github.com/alice/health/commit/c2a"], statusCode: 201),
                .json(["sha": "c2b", "url": "u", "html_url": "https://github.com/alice/health/commit/c2b"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            responses: [
                // Day-1 success.
                .json(["ref": "refs/heads/main", "object": ["sha": "c1", "type": "commit", "url": "u"]]),
                // Day-2 attempt #1 (cached parent c1) fails with 422.
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                // Day-2 attempt #2 (getRef fallback) succeeds.
                .json(["ref": "refs/heads/main", "object": ["sha": "c2b", "type": "commit", "url": "u"]])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-10"),
            files: [FileEntry(path: "2026-05-10/summary.json", data: Data("{}".utf8))]
        )
        let result = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-11"),
            files: [FileEntry(path: "2026-05-11/summary.json", data: Data("{}".utf8))]
        )

        XCTAssertEqual(result, .success(reference: "c2b", url: URL(string: "https://github.com/alice/health/commit/c2b")))

        let captured = GitHubMockTransport.captured
        // Two getRefs total: one for day-1, one for day-2's retry fallback.
        let getRefCount = captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)
        }.count
        XCTAssertEqual(getRefCount, 2, "expected one getRef per deliver: day-1 initial + day-2 422 fallback")

        // Day-2's commits must show: attempt #1 used cached c1, attempt #2 used c1real.
        let commitParents = try captured
            .filter { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }
            .compactMap { $0.httpBody }
            .map { try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: $0).parents }
        XCTAssertEqual(commitParents, [["c0"], ["c1"], ["c1real"]])
    }

    // MARK: - 4. Cache invalidated after retry exhaustion

    func testCacheInvalidatedOnExhaustedRetries() async throws {
        // Day-1 succeeds (cache = c1).
        // Day-2 returns 422 on every PATCH attempt → throws nonFastForwardExhausted.
        //   Each retry must have invalidated the cache, so by the end it's nil.
        // Day-3 must therefore re-fetch via getRef (proving the cache was
        //   cleared, not still pointing at the dead c1).

        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: [
                // Day-1 initial.
                .json(["ref": "refs/heads/main", "object": ["sha": "c0", "type": "commit", "url": "u"]]),
                // Day-2 retries (3 of them after attempt #1 wipes cache).
                .json(["ref": "refs/heads/main", "object": ["sha": "c1real", "type": "commit", "url": "u"]]),
                .json(["ref": "refs/heads/main", "object": ["sha": "c1real", "type": "commit", "url": "u"]]),
                .json(["ref": "refs/heads/main", "object": ["sha": "c1real", "type": "commit", "url": "u"]]),
                // Day-3: cache should be dead, so getRef again.
                .json(["ref": "refs/heads/main", "object": ["sha": "cAfter", "type": "commit", "url": "u"]])
            ]
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c0",
            response: .json(["sha": "c0", "tree": ["sha": "tree0", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c1",
            response: .json(["sha": "c1", "tree": ["sha": "tree1", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c1real",
            response: .json(["sha": "c1real", "tree": ["sha": "treeReal", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/cAfter",
            response: .json(["sha": "cAfter", "tree": ["sha": "treeAfter", "url": "u"]])
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
        // Day-1 commit, then 4 day-2 commits (all of which 422), then day-3 commit.
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/commits",
            responses: [
                .json(["sha": "c1", "url": "u", "html_url": "https://github.com/alice/health/commit/c1"], statusCode: 201),
                .json(["sha": "c2a", "url": "u", "html_url": "u"], statusCode: 201),
                .json(["sha": "c2b", "url": "u", "html_url": "u"], statusCode: 201),
                .json(["sha": "c2c", "url": "u", "html_url": "u"], statusCode: 201),
                .json(["sha": "c2d", "url": "u", "html_url": "u"], statusCode: 201),
                .json(["sha": "c3", "url": "u", "html_url": "https://github.com/alice/health/commit/c3"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            responses: [
                // Day-1: success.
                .json(["ref": "refs/heads/main", "object": ["sha": "c1", "type": "commit", "url": "u"]]),
                // Day-2: 4 attempts, all 422.
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                // Day-3: success.
                .json(["ref": "refs/heads/main", "object": ["sha": "c3", "type": "commit", "url": "u"]])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-10"),
            files: [FileEntry(path: "2026-05-10/summary.json", data: Data("{}".utf8))]
        )
        do {
            _ = try await sink.deliver(
                snapshot: makeSnapshot(dayKey: "2026-05-11"),
                files: [FileEntry(path: "2026-05-11/summary.json", data: Data("{}".utf8))]
            )
            XCTFail("expected day-2 to exhaust retries")
        } catch GitHubSinkError.nonFastForwardExhausted {
            // expected
        }

        // Record getRef count up to the failure, then make sure day-3 adds one more.
        let getRefBeforeDay3 = GitHubMockTransport.captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)
        }.count

        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-12"),
            files: [FileEntry(path: "2026-05-12/summary.json", data: Data("{}".utf8))]
        )

        let getRefAfterDay3 = GitHubMockTransport.captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)
        }.count
        XCTAssertEqual(
            getRefAfterDay3 - getRefBeforeDay3, 1,
            "after exhausted retries the cache must be dead, forcing day-3 to re-fetch via getRef"
        )

        // The day-3 commit must have built its parent off the fresh getRef
        // (cAfter), not the dead day-1 SHA (c1).
        let commitParents = try GitHubMockTransport.captured
            .filter { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }
            .compactMap { $0.httpBody }
            .map { try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: $0).parents }
        XCTAssertEqual(commitParents.last, ["cAfter"], "day-3 must commit against the freshly-fetched ref, not the dead cache")
    }

    // MARK: - 5. Cache captures the SHA from a successful retry, not the failed attempt

    func testCacheHoldsSuccessfulRetrySha() async throws {
        // First deliver: attempt 0 PATCH returns 422 (no cache existed, getRef
        // gave us c0 which was actually stale). Retry pulls a fresh ref
        // (c0real), pushes against it, succeeds with commitSha c1.
        // Then a second deliver MUST treat c1 as the cached parent — proving
        // that the cache was written from the successful retry's commit SHA,
        // not the failed attempt's pre-PATCH state.

        GitHubMockTransport.addRouteSequence(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            responses: [
                // Deliver-1 attempt 0: stale ref.
                .json(["ref": "refs/heads/main", "object": ["sha": "c0", "type": "commit", "url": "u"]]),
                // Deliver-1 attempt 1: fresh ref after 422 cleared the cache.
                .json(["ref": "refs/heads/main", "object": ["sha": "c0real", "type": "commit", "url": "u"]])
            ]
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c0",
            response: .json(["sha": "c0", "tree": ["sha": "tree0", "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c0real",
            response: .json(["sha": "c0real", "tree": ["sha": "tree0real", "url": "u"]])
        )
        // Deliver-2 reads getCommit against the cached SHA c1 — proving the
        // cache picked up the successful retry's commit SHA.
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/c1",
            response: .json(["sha": "c1", "tree": ["sha": "tree1", "url": "u"]])
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
        GitHubMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/git/commits",
            responses: [
                // Deliver-1 attempt 0 (rejected).
                .json(["sha": "c1a", "url": "u", "html_url": "u"], statusCode: 201),
                // Deliver-1 attempt 1 (accepted).
                .json(["sha": "c1", "url": "u", "html_url": "https://github.com/alice/health/commit/c1"], statusCode: 201),
                // Deliver-2 (accepted, against cached c1).
                .json(["sha": "c2", "url": "u", "html_url": "https://github.com/alice/health/commit/c2"], statusCode: 201)
            ]
        )
        GitHubMockTransport.addRouteSequence(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            responses: [
                // Deliver-1 attempt 0: 422.
                .json(["message": "Update is not a fast forward."], statusCode: 422),
                // Deliver-1 attempt 1: success.
                .json(["ref": "refs/heads/main", "object": ["sha": "c1", "type": "commit", "url": "u"]]),
                // Deliver-2: success.
                .json(["ref": "refs/heads/main", "object": ["sha": "c2", "type": "commit", "url": "u"]])
            ]
        )

        let sink = GitHubSink(credentialProvider: credentialProvider, session: .shared)
        _ = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-10"),
            files: [FileEntry(path: "2026-05-10/summary.json", data: Data("{}".utf8))]
        )
        let result = try await sink.deliver(
            snapshot: makeSnapshot(dayKey: "2026-05-11"),
            files: [FileEntry(path: "2026-05-11/summary.json", data: Data("{}".utf8))]
        )

        XCTAssertEqual(result, .success(reference: "c2", url: URL(string: "https://github.com/alice/health/commit/c2")))

        let captured = GitHubMockTransport.captured
        // Two getRefs total — both inside deliver-1. Deliver-2 must skip getRef
        // because the cache (c1, from the successful retry) drives the parent.
        let getRefCount = captured.filter {
            $0.httpMethod == "GET" && ($0.url?.absoluteString.hasSuffix("/git/ref/heads/main") ?? false)
        }.count
        XCTAssertEqual(getRefCount, 2, "deliver-2 must use the cached SHA from deliver-1's successful retry")

        let commitParents = try captured
            .filter { $0.httpMethod == "POST" && ($0.url?.absoluteString.hasSuffix("/git/commits") ?? false) }
            .compactMap { $0.httpBody }
            .map { try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: $0).parents }
        XCTAssertEqual(commitParents, [["c0"], ["c0real"], ["c1"]],
                       "deliver-2's parent must be c1 (from deliver-1's successful retry), not c1a or c0")
    }

    // MARK: - helpers

    private func installHappyPathRoutes(parentSha: String, parentTreeSha: String, commitSha: String, treeSha: String, blobSha: String) {
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/ref/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": parentSha, "type": "commit", "url": "u"]
            ])
        )
        GitHubMockTransport.addRoute(
            method: "GET",
            pathSuffix: "/git/commits/\(parentSha)",
            response: .json(["sha": parentSha, "tree": ["sha": parentTreeSha, "url": "u"]])
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/blobs",
            response: .json(["sha": blobSha, "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/trees",
            response: .json(["sha": treeSha, "url": "u"], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/git/commits",
            response: .json([
                "sha": commitSha,
                "url": "u",
                "html_url": "https://github.com/alice/health/commit/\(commitSha)"
            ], statusCode: 201)
        )
        GitHubMockTransport.addRoute(
            method: "PATCH",
            pathSuffix: "/git/refs/heads/main",
            response: .json([
                "ref": "refs/heads/main",
                "object": ["sha": commitSha, "type": "commit", "url": "u"]
            ])
        )
    }

    private func makeSnapshot(dayKey: String) -> DailySnapshot {
        var snap = DailySnapshot(
            date: SampleFixtures.iso("\(dayKey)T00:00:00Z"),
            timezone: "UTC",
            generatedAt: SampleFixtures.iso("\(dayKey)T22:30:12Z"),
            deviceName: "iPhone 16 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = ["steps": SummaryFragment(metrics: ["total": .int(1000)], unit: "count")]
        return snap
    }
}
