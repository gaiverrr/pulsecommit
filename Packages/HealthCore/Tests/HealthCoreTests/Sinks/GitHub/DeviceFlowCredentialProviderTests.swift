import XCTest
@testable import HealthCore

final class DeviceFlowCredentialProviderTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        GitHubMockTransport.register()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitHubMockTransport.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        GitHubMockTransport.unregister()
        super.tearDown()
    }

    private func makeClient() -> GitHubDeviceFlowClient {
        GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
    }

    // No live-Date default: every test must pin its clock so CI timing
    // can never shift a token across an expiry boundary mid-test.
    private func makeProvider(vault: TokenVault, clock: @escaping @Sendable () -> Date) -> DeviceFlowCredentialProvider {
        DeviceFlowCredentialProvider(
            vault: vault,
            client: makeClient(),
            clock: clock,
            owner: "octocat",
            repo: "hello",
            branch: "main",
            subdir: ""
        )
    }

    func testThrowsSessionExpiredWhenVaultEmpty() async {
        let vault = InMemoryTokenVault(initial: nil)
        let provider = makeProvider(vault: vault, clock: { Date(timeIntervalSince1970: 1_750_000_000) })
        do {
            _ = try await provider.accessToken()
            XCTFail("expected throw")
        } catch let err as GitHubAuthError {
            XCTAssertEqual(err, .sessionExpired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testReturnsCachedTokenWhenValid() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_valid",
            refreshToken: "ghr_v",
            accessExpiresAt: now.addingTimeInterval(3600),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        let vault = InMemoryTokenVault(initial: stored)
        let provider = makeProvider(vault: vault, clock: { now })

        let token = try await provider.accessToken()
        XCTAssertEqual(token, "gho_valid")

        let refreshCount = GitHubMockTransport.captured.filter { Self.isRefresh($0) }.count
        XCTAssertEqual(refreshCount, 0)
    }

    func testRefreshesWhenAccessTokenExpired() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        let vault = InMemoryTokenVault(initial: stored)

        let newPair = TokenPair(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let provider = makeProvider(vault: vault, clock: { now })

        let token = try await provider.accessToken()
        XCTAssertEqual(token, "gho_new")

        let loaded = try await vault.load()
        XCTAssertEqual(loaded?.accessToken, "gho_new")
        XCTAssertEqual(loaded?.refreshToken, "ghr_new")
    }

    func testSessionExpiredOnRefresh401ClearsVault() async {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        let vault = InMemoryTokenVault(initial: stored)
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.failure(.sessionExpired)))

        let provider = makeProvider(vault: vault, clock: { now })

        do {
            _ = try await provider.accessToken()
            XCTFail("expected throw")
        } catch let err as GitHubAuthError {
            XCTAssertEqual(err, .sessionExpired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let loaded = try? await vault.load()
        XCTAssertNil(loaded)
    }

    /// Tokens stored with `refreshToken == nil` (GitHub Apps with token expiration
    /// disabled) must not trigger a refresh network call — that would always 401
    /// and silently force the user to re-auth. Provider should fail fast with
    /// `.sessionExpired` and clear the vault.
    func testNilRefreshTokenSurfacesSessionExpiredWithoutNetworkCall() async {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "ghu_only_access",
            refreshToken: nil,
            accessExpiresAt: now.addingTimeInterval(30),  // already inside the 60s pre-expiry window
            refreshExpiresAt: .distantFuture
        )
        let vault = InMemoryTokenVault(initial: stored)
        // No mock routes registered — any HTTP attempt would fail the test
        // because the URLSession would attempt a real network call.

        let provider = makeProvider(vault: vault, clock: { now })

        do {
            _ = try await provider.accessToken()
            XCTFail("expected throw")
        } catch let err as GitHubAuthError {
            XCTAssertEqual(err, .sessionExpired)
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let loaded = try? await vault.load()
        XCTAssertNil(loaded, "vault should be cleared after empty-refresh sessionExpired")
        XCTAssertTrue(GitHubMockTransport.captured.isEmpty, "no network calls should be made for empty refresh token")
    }

    /// Regression for pc-0we: a refresh task that is cancelled AFTER the new
    /// tokens have already landed in the vault must not roll back the save.
    /// Cancellation at that point reflects the user dismissing the auth sheet
    /// (which triggers `invalidateSession()` → cancels the in-flight refresh
    /// task), not invalid tokens — wiping them would force a gratuitous
    /// re-auth on the next run.
    ///
    /// We use a `CancelOnSaveVault` that calls `provider.invalidateSession()`
    /// at the moment `save` completes — that's the public path which cancels
    /// the refresh task internally and recreates the exact race window the
    /// original code wiped tokens in.
    func testCancellationAfterSuccessfulSaveDoesNotClearVault() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )

        let newPair = TokenPair(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let providerHolder = ProviderHolder()
        let vault = CancelOnSaveVault(initial: stored, providerHolder: providerHolder)

        let provider = makeProvider(vault: vault, clock: { now })
        await providerHolder.set(provider)

        // With the pc-0we fix, the post-save Task.isCancelled check is gone,
        // so accessToken() returns the freshly refreshed token to the caller.
        // The OLD code would throw CancellationError here.
        let token = try await provider.accessToken()
        XCTAssertEqual(
            token,
            "gho_new",
            "caller must receive the refreshed token even if invalidateSession races mid-refresh"
        )
    }

    /// When `vault.load()` throws (e.g. KeychainSecretsStore propagates
    /// `errSecInteractionNotAllowed` because the device is locked), the
    /// provider must re-throw without clearing the vault. Clearing on
    /// transient keychain unavailability would silently force the user to
    /// re-authenticate next launch.
    func testVaultLoadErrorIsRethrownWithoutClearingVault() async {
        struct LoadError: Error, Equatable {}
        let vault = LoadObservingVault(loadError: LoadError())
        let provider = makeProvider(vault: vault, clock: { Date(timeIntervalSince1970: 1_750_000_000) })

        do {
            _ = try await provider.accessToken()
            XCTFail("expected throw")
        } catch is LoadError {
            // ok
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let clearCount = await vault.clearCallCount
        XCTAssertEqual(clearCount, 0, "vault must not be cleared on transient load error")
    }

    func testConcurrentCallersTriggerSingleRefresh() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        let vault = InMemoryTokenVault(initial: stored)

        let newPair = TokenPair(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let provider = makeProvider(vault: vault, clock: { now })

        let results = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for _ in 0..<10 {
                group.addTask { try await provider.accessToken() }
            }
            var out: [String] = []
            for try await value in group { out.append(value) }
            return out
        }

        XCTAssertEqual(results.count, 10)
        for token in results {
            XCTAssertEqual(token, "gho_new")
        }

        let refreshCount = GitHubMockTransport.captured.filter { Self.isRefresh($0) }.count
        XCTAssertEqual(refreshCount, 1, "concurrent callers must single-flight refresh")
    }

    /// The single-flight task performs the load internally, so a slow keychain
    /// read parks every concurrent caller on the SAME task instead of letting
    /// each start its own load + refresh. Caller A creates and stalls the task;
    /// caller B arrives mid-flight and joins it. Releasing the stall drives one
    /// refresh; both callers observe the refreshed token and no second refresh
    /// is issued (a stale pre-refresh snapshot is now structurally impossible).
    func testConcurrentCallersJoinStalledSingleFlightLoad() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )

        let newPair = TokenPair(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        // Only register ONE refresh route — a second refresh attempt would fail.
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let vault = StallableVault(initial: stored)
        let provider = makeProvider(vault: vault, clock: { now })

        // Caller A creates the single-flight task and parks inside load().
        await vault.armStallOnNextLoad()
        async let aToken = provider.accessToken()

        // Wait until A is parked inside load().
        for _ in 0..<200 where await vault.loadInFlight == false {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let inFlight = await vault.loadInFlight
        XCTAssertTrue(inFlight, "caller A should be suspended inside vault.load()")

        // Caller B arrives while the task is in flight and must join it rather
        // than start a second load/refresh. Do NOT await B before releasing the
        // stall — B is parked on the same stalled task.
        async let bToken = provider.accessToken()

        await vault.releaseStall()

        let aTokenValue = try await aToken
        let bTokenValue = try await bToken
        XCTAssertEqual(aTokenValue, "gho_new", "caller A must return the refreshed token")
        XCTAssertEqual(bTokenValue, "gho_new", "caller B must join the in-flight task, not refresh again")

        let refreshCount = GitHubMockTransport.captured.filter { Self.isRefresh($0) }.count
        XCTAssertEqual(refreshCount, 1, "a stalled single-flight load must still refresh exactly once")
    }

    /// Stress the single-flight guarantee against the stale-snapshot race: 20
    /// concurrent callers starting from an expired access token must collapse to
    /// EXACTLY ONE `client.refresh`. A caller that happens to arrive after the
    /// refresh already completed builds a fresh task that reloads the persisted
    /// tokens and returns without a second refresh — so it can never round-trip
    /// with the already-rotated (single-use) refresh token.
    func testManyConcurrentCallersTriggerSingleRefresh() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        let vault = InMemoryTokenVault(initial: stored)

        let newPair = TokenPair(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        // Only ONE refresh route — a second refresh attempt would 404 and fail.
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let provider = makeProvider(vault: vault, clock: { now })

        let results = try await withThrowingTaskGroup(of: String.self) { group -> [String] in
            for _ in 0..<20 {
                group.addTask { try await provider.accessToken() }
            }
            var out: [String] = []
            for try await value in group { out.append(value) }
            return out
        }

        XCTAssertEqual(results.count, 20)
        for token in results {
            XCTAssertEqual(token, "gho_new")
        }

        let refreshCount = GitHubMockTransport.captured.filter { Self.isRefresh($0) }.count
        XCTAssertEqual(refreshCount, 1, "20 concurrent callers must single-flight to exactly one refresh")
    }

    /// A second call arriving after a refresh already completed must reload the
    /// freshly persisted tokens and return them without refreshing again — the
    /// stale-snapshot interleaving where a late caller re-refreshes with an
    /// already-rotated refresh token.
    func testSecondCallAfterRefreshDoesNotRefreshAgain() async throws {
        let now = Date()
        let stored = StoredTokens(
            accessToken: "gho_old",
            refreshToken: "ghr_old",
            accessExpiresAt: now.addingTimeInterval(30),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        let vault = InMemoryTokenVault(initial: stored)

        let newPair = TokenPair(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let provider = makeProvider(vault: vault, clock: { now })

        let first = try await provider.accessToken()
        XCTAssertEqual(first, "gho_new")
        let second = try await provider.accessToken()
        XCTAssertEqual(second, "gho_new")

        let refreshCount = GitHubMockTransport.captured.filter { Self.isRefresh($0) }.count
        XCTAssertEqual(refreshCount, 1, "the second call must reuse persisted tokens, not refresh again")
    }

    private actor StallableVault: TokenVault {
        private var tokens: StoredTokens?
        private var stallNextLoad = false
        private var continuation: CheckedContinuation<Void, Never>?
        private(set) var loadInFlight = false

        init(initial: StoredTokens?) {
            self.tokens = initial
        }

        func armStallOnNextLoad() {
            stallNextLoad = true
        }

        func releaseStall() {
            continuation?.resume()
            continuation = nil
        }

        func load() async throws -> StoredTokens? {
            if stallNextLoad {
                stallNextLoad = false
                // Snapshot tokens BEFORE stalling so the returned value is what
                // the caller "saw" at the moment they called load() — even if
                // another writer mutates `tokens` while we wait. This models
                // a slow keychain read that completes after a peer's save.
                let snapshot = tokens
                loadInFlight = true
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    continuation = cont
                }
                loadInFlight = false
                return snapshot
            }
            return tokens
        }

        func save(_ tokens: StoredTokens) async throws {
            self.tokens = tokens
        }

        func clear() async throws {
            tokens = nil
        }
    }

    private actor LoadObservingVault: TokenVault {
        private let loadError: Error
        private(set) var clearCallCount = 0

        init(loadError: Error) {
            self.loadError = loadError
        }

        func load() async throws -> StoredTokens? {
            throw loadError
        }

        func save(_ tokens: StoredTokens) async throws {}

        func clear() async throws {
            clearCallCount += 1
        }
    }

    private static func isRefresh(_ request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        guard url.host == "github.com", url.path == "/login/oauth/access_token" else { return false }
        guard let body = request.httpBody, let s = String(data: body, encoding: .utf8) else { return false }
        return s.contains("grant_type=refresh_token")
    }
}

/// Holds the provider so the vault can call `invalidateSession()` mid-refresh.
private actor ProviderHolder {
    private var provider: DeviceFlowCredentialProvider?

    func set(_ provider: DeviceFlowCredentialProvider) {
        self.provider = provider
    }

    func invalidate() async {
        await provider?.invalidateSession()
    }
}

/// Vault that triggers `invalidateSession()` on the provider the moment `save`
/// lands, recreating the pc-0we race: the in-flight refresh task gets
/// cancelled AFTER it has already persisted valid tokens. The old code wiped
/// them via a post-save `Task.isCancelled` check.
private actor CancelOnSaveVault: TokenVault {
    private var tokens: StoredTokens?
    private let providerHolder: ProviderHolder

    init(initial: StoredTokens?, providerHolder: ProviderHolder) {
        self.tokens = initial
        self.providerHolder = providerHolder
    }

    func load() async throws -> StoredTokens? { tokens }

    func save(_ tokens: StoredTokens) async throws {
        self.tokens = tokens
        await providerHolder.invalidate()
        // Yield so the cancellation lands before the refresh task body
        // proceeds past the save call site.
        await Task.yield()
    }

    func clear() async throws { tokens = nil }
}
