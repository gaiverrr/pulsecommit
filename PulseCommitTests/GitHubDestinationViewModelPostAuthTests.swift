import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class GitHubDestinationViewModelPostAuthTests: XCTestCase {

    private func makePreferences(owner: String? = nil, repo: String? = nil, branch: String? = nil) -> PreferencesStore {
        let suite = "GitHubDestinationViewModelPostAuthTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let prefs = PreferencesStore(defaults: defaults)
        prefs.githubOwner = owner
        prefs.githubRepo = repo
        prefs.githubBranch = branch
        return prefs
    }

    private func sampleStoredTokens() -> StoredTokens {
        StoredTokens(
            accessToken: "gho_access",
            refreshToken: "ghr_refresh",
            accessExpiresAt: Date(timeIntervalSinceNow: 28_800),
            refreshExpiresAt: Date(timeIntervalSinceNow: 15_552_000)
        )
    }

    private func makeStream(emitting events: [DeviceFlowSession.State]) -> AsyncStream<DeviceFlowSession.State> {
        AsyncStream { continuation in
            for event in events {
                continuation.yield(event)
            }
            continuation.finish()
        }
    }

    private func waitFor(
        _ predicate: @escaping @MainActor () -> Bool,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for device-flow state")
    }

    func test_observeSession_completed_withEmptyPrefs_movesToPickingRepo() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let stored = sampleStoredTokens()
        try await vault.save(stored)

        let vm = GitHubDestinationViewModel(
            initialState: .awaitingApproval,
            preferences: prefs,
            vault: vault
        )

        let stream = makeStream(emitting: [.approving, .completed(stored)])
        await vm.observeSession(stream)

        XCTAssertEqual(vm.state, .pickingRepo)
    }

    func test_observeSession_completed_withPopulatedPrefs_movesToConnected() async throws {
        let prefs = makePreferences(owner: "yuriy", repo: "health", branch: "main")
        let vault = InMemoryTokenVault()
        let stored = sampleStoredTokens()
        try await vault.save(stored)

        let vm = GitHubDestinationViewModel(
            initialState: .awaitingApproval,
            preferences: prefs,
            vault: vault
        )

        let stream = makeStream(emitting: [.approving, .completed(stored)])
        await vm.observeSession(stream)

        XCTAssertEqual(vm.state, .connected)
    }

    /// A failed device flow keeps the destination in .awaitingApproval so the
    /// device-code sheet (which deliberately does not auto-dismiss on .failed)
    /// stays presented with the error message. The user leaves via Cancel or
    /// swipe-down, both of which reset the state to .disconnected.
    func test_observeSession_failed_keepsAwaitingApprovalSoSheetShowsError() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let vm = GitHubDestinationViewModel(
            initialState: .awaitingApproval,
            preferences: prefs,
            vault: vault
        )

        let stream = makeStream(emitting: [.failed(.codeExpired)])
        await vm.observeSession(stream)

        XCTAssertEqual(vm.state, .awaitingApproval)
    }

    /// Regression for the post-Authorize black-screen bug: when the multi-cast
    /// observer fires `.completed` while the device-code sheet is still in the
    /// process of being torn down, the destination VM must still resolve to
    /// `.pickingRepo` so the host view can present the installation picker.
    /// The view-side fix presents the picker via `onChange(of: viewModel.state)`
    /// at the root of `GitHubDestinationView` rather than via the (about-to-
    /// dismiss) device-code sheet's `onChange`.
    func test_observeSession_completed_whileDeviceCodeSheetStillPresented_resolvesToPickingRepo() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let stored = sampleStoredTokens()
        try await vault.save(stored)

        let vm = GitHubDestinationViewModel(
            initialState: .awaitingApproval,
            preferences: prefs,
            vault: vault
        )

        // Simulate the exact race: the device-code sheet is still presented
        // (state == .awaitingApproval) when the observer multi-casts .completed.
        XCTAssertEqual(vm.state, .awaitingApproval)
        let stream = makeStream(emitting: [.completed(stored)])
        await vm.observeSession(stream)

        // The destination VM must advance to .pickingRepo so the root
        // onChange(of: viewModel.state) handler can materialise the picker VM.
        XCTAssertEqual(vm.state, .pickingRepo)
    }

    func test_observeSession_cancelled_movesToDisconnected() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let vm = GitHubDestinationViewModel(
            initialState: .awaitingApproval,
            preferences: prefs,
            vault: vault
        )

        let stream = makeStream(emitting: [.cancelled])
        await vm.observeSession(stream)

        XCTAssertEqual(vm.state, .disconnected)
    }

    func test_cancelledDestination_ignoresLateCompletionFromReplacedAttempt() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let vm = GitHubDestinationViewModel(
            initialState: .awaitingApproval,
            preferences: prefs,
            vault: vault
        )

        vm.cancel()
        let stream = makeStream(emitting: [.completed(sampleStoredTokens())])
        await vm.observeSession(stream)

        XCTAssertEqual(vm.state, .disconnected)
    }

    func test_failedAttempt_retryCompletionUsesFreshAttemptAndIgnoresOldEvents() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let vm = GitHubDestinationViewModel(preferences: prefs, vault: vault)

        let failedAttempt = vm.connect()
        await vm.observeSession(
            makeStream(emitting: [.failed(.network(URLError(.notConnectedToInternet)))]),
            attemptID: failedAttempt
        )
        XCTAssertEqual(vm.state, .awaitingApproval)

        let retryAttempt = vm.connect()
        await vm.observeSession(
            makeStream(emitting: [.completed(sampleStoredTokens())]),
            attemptID: failedAttempt
        )
        XCTAssertEqual(vm.state, .awaitingApproval)

        await vm.observeSession(
            makeStream(emitting: [.completed(sampleStoredTokens())]),
            attemptID: retryAttempt
        )
        XCTAssertEqual(vm.state, .pickingRepo)
    }

    func test_realSessions_startFailureThenFreshRetryCompletesRepositoryHandoff() async throws {
        let prefs = makePreferences()
        let vault = InMemoryTokenVault()
        let destination = GitHubDestinationViewModel(preferences: prefs, vault: vault)

        let failedSession = DeviceFlowSession(
            vault: vault,
            start: { throw URLError(.notConnectedToInternet) },
            poll: { _, _, _ in throw GitHubAuthError.codeExpired }
        )
        let failedFlow = DeviceFlowViewModel.live(session: failedSession)
        let failedAttempt = destination.connect()
        let failedStates = await failedSession.observe()
        let failedObservation = Task {
            await destination.observeSession(failedStates, attemptID: failedAttempt)
        }
        failedFlow.begin()

        try await waitFor { failedFlow.state == .failed }
        _ = await failedObservation.value
        XCTAssertEqual(destination.state, .awaitingApproval)
        XCTAssertNil(failedFlow.userCode)
        XCTAssertNil(failedFlow.verificationURI)

        let response = DeviceCodeResponse(
            deviceCode: "fresh-device-code",
            userCode: "WXYZ-9876",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: URL(string: "https://github.com/login/device?user_code=WXYZ-9876")!,
            expiresIn: 900,
            interval: 5,
            expiresAt: Date(timeIntervalSinceNow: 900)
        )
        let pair = TokenPair(
            accessToken: "gho_fresh",
            refreshToken: "ghr_fresh",
            accessExpiresAt: Date(timeIntervalSinceNow: 28_800),
            refreshExpiresAt: Date(timeIntervalSinceNow: 15_552_000)
        )
        let retrySession = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in pair }
        )
        let retryFlow = DeviceFlowViewModel.live(session: retrySession)
        let retryAttempt = destination.connect()
        let retryStates = await retrySession.observe()
        let retryObservation = Task {
            await destination.observeSession(retryStates, attemptID: retryAttempt)
        }
        retryFlow.begin()

        try await waitFor { retryFlow.state == .completed }
        _ = await retryObservation.value

        XCTAssertEqual(destination.state, .pickingRepo)
        let storedTokens = try await vault.load()
        XCTAssertEqual(storedTokens?.accessToken, "gho_fresh")
    }
}
