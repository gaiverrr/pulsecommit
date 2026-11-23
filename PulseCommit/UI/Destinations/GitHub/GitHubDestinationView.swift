import Foundation
import Observation
import SwiftUI
import HealthCore

@MainActor
@Observable
final class GitHubDestinationViewModel {
    enum State: Equatable {
        case disconnected
        case awaitingApproval
        case pickingRepo
        case connected
    }

    var state: State

    private var preferences: PreferencesStore?
    private var vault: TokenVault?
    private var activeAttemptID: UUID?

    init(
        initialState: State = .disconnected,
        preferences: PreferencesStore? = nil,
        vault: TokenVault? = nil
    ) {
        self.state = initialState
        self.preferences = preferences
        self.vault = vault
    }

    func bindContext(preferences: PreferencesStore, vault: TokenVault) {
        self.preferences = preferences
        self.vault = vault
    }

    @discardableResult
    func connect() -> UUID {
        let attemptID = UUID()
        activeAttemptID = attemptID
        state = .awaitingApproval
        return attemptID
    }

    func cancel() {
        activeAttemptID = nil
        state = .disconnected
    }

    func canStartAttempt(deviceFlowState: DeviceFlowViewModel.DisplayState?) -> Bool {
        if state == .disconnected {
            return deviceFlowState == nil
        }
        return state == .awaitingApproval && deviceFlowState == .failed
    }

    func handleSession(_ display: DeviceFlowViewModel.DisplayState) {
        switch display {
        case .completed:
            state = advanceStateAfterCompletion()
        case .cancelled:
            state = .disconnected
        case .failed, .idle, .awaitingApproval, .approving:
            // .failed keeps .awaitingApproval so the device-code sheet stays
            // presented showing the error; the user exits via Cancel/swipe,
            // which resets to .disconnected.
            break
        }
    }

    /// Consumes a `DeviceFlowSession.State` stream and advances `state` when the
    /// session reaches a terminal event. Owning the subscription here (instead of
    /// in the view) keeps the post-Authorize hand-off alive even if the
    /// device-code sheet is torn down before `.completed` propagates.
    func observeSession(
        _ states: AsyncStream<DeviceFlowSession.State>,
        attemptID: UUID? = nil
    ) async {
        let observedAttemptID = attemptID ?? activeAttemptID
        for await next in states {
            if Task.isCancelled { return }
            guard state == .awaitingApproval,
                  observedAttemptID == activeAttemptID else {
                return
            }
            switch next {
            case .completed:
                activeAttemptID = nil
                state = advanceStateAfterCompletion()
            case .cancelled:
                activeAttemptID = nil
                state = .disconnected
            case .failed, .idle, .awaitingApproval, .approving:
                // .failed is terminal for the session stream but must not tear
                // down the sheet — the error stays on screen until the user
                // dismisses (bindingSheet/onDismiss handle the state reset).
                continue
            }
        }
    }

    private func advanceStateAfterCompletion() -> State {
        if hasPopulatedPrefs() {
            return .connected
        }
        return .pickingRepo
    }

    private func hasPopulatedPrefs() -> Bool {
        guard let prefs = preferences else { return false }
        let owner = prefs.githubOwner ?? ""
        let repo = prefs.githubRepo ?? ""
        let branch = prefs.githubBranch ?? ""
        return !owner.isEmpty && !repo.isEmpty && !branch.isEmpty
    }

    func pickerCompleted() {
        state = .connected
    }

    func pickerCancelled() {
        state = .disconnected
    }

    func disconnect() {
        state = .disconnected
    }
}

struct GitHubDestinationView: View {
    @EnvironmentObject var container: AppContainer
    @State private var viewModel: GitHubDestinationViewModel
    @State private var deviceFlow: DeviceFlowViewModel?
    @State private var connectedViewModel: GitHubConnectedViewModel?
    @State private var connectedOwnerRepo: String?
    @State private var showBranchPicker = false
    @State private var showSubdirEdit = false
    @State private var installationPicker: GitHubInstallationPickerViewModel?
    @State private var sessionObservationTask: Task<Void, Never>?

    init(viewModel: GitHubDestinationViewModel? = nil) {
        if let vm = viewModel {
            _viewModel = State(initialValue: vm)
        } else {
            _viewModel = State(initialValue: GitHubDestinationViewModel())
        }
    }

    var body: some View {
        Group {
            switch viewModel.state {
            case .disconnected:
                GitHubDisconnectedView(onConnect: onConnectTapped)
            case .awaitingApproval:
                GitHubDisconnectedView(onConnect: onConnectTapped)
                    .disabled(true)
            case .pickingRepo:
                GitHubDisconnectedView(onConnect: onConnectTapped)
                    .disabled(true)
            case .connected:
                connectedView
            }
        }
        .sheet(isPresented: bindingSheet) {
            if let vm = deviceFlow {
                GitHubDeviceCodeSheet(
                    viewModel: vm,
                    onDismiss: {
                        deviceFlow = nil
                        // After a terminal .failed the session's observer streams
                        // are already finished, so a subsequent Cancel never
                        // reaches observeSession — reset the destination state
                        // here instead.
                        if viewModel.state == .awaitingApproval {
                            viewModel.cancel()
                        }
                    },
                    onRetry: startDeviceFlowAttempt
                )
                .id(vm.id)
                .onChange(of: vm.state) { _, newState in
                    // .failed deliberately omitted: the sheet stays open to
                    // show the error (see GitHubDeviceCodeSheet.shouldDismiss).
                    if newState == .completed || newState == .cancelled {
                        deviceFlow = nil
                    }
                }
            }
        }
        .onChange(of: viewModel.state) { _, newState in
            // Eagerly construct the installation-picker VM when the destination
            // VM advances to .pickingRepo. We can't rely on the device-code
            // sheet's .onChange of vm.state because the multi-cast observer in
            // `observeSession` may transition the destination state BEFORE the
            // device-code sheet's onChange fires (race) — that left the
            // installationPicker == nil and the .sheet(isPresented:) showed an
            // empty black background instead of the picker.
            if newState == .pickingRepo && installationPicker == nil {
                installationPicker = makeInstallationPickerVM()
            }
        }
        .sheet(isPresented: $showBranchPicker, onDismiss: refreshConnectedFromPrefs) {
            if let owner = container.preferences.githubOwner,
               let repo = container.preferences.githubRepo,
               let provider = container.githubCredentialProvider() {
                let token: @Sendable () async throws -> String = {
                    try await provider.accessToken()
                }
                GitHubBranchPickerSheet(
                    viewModel: GitHubBranchPickerViewModel.live(
                        owner: owner,
                        repo: repo,
                        fetcher: GitHubBranchFetcher(),
                        token: token,
                        preferences: container.preferences,
                        onDismiss: { showBranchPicker = false },
                        onSessionExpired: handleSessionExpired
                    )
                )
            }
        }
        .sheet(isPresented: installationPickerBinding) {
            if let vm = installationPicker {
                GitHubInstallationPickerSheet(viewModel: vm)
            }
        }
        .sheet(isPresented: $showSubdirEdit, onDismiss: refreshConnectedFromPrefs) {
            GitHubSubdirEditSheet(
                viewModel: GitHubSubdirEditViewModel.live(
                    initial: container.preferences.githubSubdir ?? "",
                    preferences: container.preferences,
                    onDismiss: { showSubdirEdit = false }
                )
            )
        }
        .onAppear(perform: bootstrapState)
        .onDisappear {
            if viewModel.state == .awaitingApproval, let vm = deviceFlow {
                vm.cancel()
                if vm.state == .failed {
                    // Failure is already terminal, so there is no in-flight
                    // token write to serialize before making reconnect usable.
                    deviceFlow = nil
                    viewModel.cancel()
                    sessionObservationTask?.cancel()
                    sessionObservationTask = nil
                }
            } else {
                sessionObservationTask?.cancel()
                sessionObservationTask = nil
            }
        }
    }

    private var bindingSheet: Binding<Bool> {
        Binding(
            get: { viewModel.state == .awaitingApproval && deviceFlow != nil },
            set: { isPresented in
                if !isPresented {
                    let failed = deviceFlow?.state == .failed
                    deviceFlow?.cancel()
                    deviceFlow = nil
                    // A failed session has already finished all destination
                    // observers, so no later `.cancelled` event can reset it.
                    if failed && viewModel.state == .awaitingApproval {
                        viewModel.cancel()
                    }
                }
            }
        )
    }

    private var installationPickerBinding: Binding<Bool> {
        Binding(
            get: { viewModel.state == .pickingRepo },
            set: { isPresented in
                if !isPresented {
                    installationPicker = nil
                    if viewModel.state == .pickingRepo {
                        cancelPickerAndClearTokens()
                    }
                }
            }
        )
    }

    private func cancelPickerAndClearTokens() {
        viewModel.pickerCancelled()
        container.invalidateGithubCredentialProvider()
        let vault = KeychainTokenVault(secrets: container.secrets)
        Task { try? await vault.clear() }
    }

    private func handleSessionExpired() {
        let vault = KeychainTokenVault(secrets: container.secrets)
        let prefs = container.preferences
        let cachedProvider = container.githubCredentialProvider()
        connectedViewModel = nil
        connectedOwnerRepo = nil
        container.invalidateGithubCredentialProvider()
        showBranchPicker = false
        viewModel.disconnect()
        Task {
            if let provider = cachedProvider {
                await provider.invalidateSession()
            }
            try? await vault.clear()
            await MainActor.run {
                prefs.githubOwner = nil
                prefs.githubRepo = nil
                prefs.githubBranch = nil
                prefs.githubSubdir = nil
                prefs.githubInstallationId = nil
            }
        }
    }

    @ViewBuilder
    private var connectedView: some View {
        if let owner = container.preferences.githubOwner,
           let repo = container.preferences.githubRepo,
           let branch = container.preferences.githubBranch,
           !branch.isEmpty {
            let vm = ensureConnectedViewModel(owner: owner, repo: repo, branch: branch)
            GitHubConnectedView(
                viewModel: vm,
                onEditBranch: { showBranchPicker = true },
                onEditSubdir: { showSubdirEdit = true },
                consentScope: HealthExportConsentScope(
                    destination: .github(
                        owner: owner,
                        repo: repo,
                        branch: branch,
                        subdir: container.preferences.githubSubdir ?? ""
                    ),
                    enabledCategoryIds: container.preferences.enabledCategoryIds
                ),
                consentStore: container.consentStore,
                onAllowConsent: { scope in await container.acceptConsentIfCurrent(scope) }
            )
        } else {
            GitHubDisconnectedView(onConnect: onConnectTapped)
        }
    }

    private func ensureConnectedViewModel(owner: String, repo: String, branch: String) -> GitHubConnectedViewModel {
        let subdir = container.preferences.githubSubdir ?? ""
        let key = "\(owner)/\(repo)/\(branch)/\(subdir)"
        if connectedOwnerRepo == key, let existing = connectedViewModel {
            return existing
        }
        if connectedOwnerRepo != nil {
            container.invalidateGithubCredentialProvider()
        }
        let vault = KeychainTokenVault(secrets: container.secrets)
        let provider = container.githubCredentialProvider() ?? DeviceFlowCredentialProvider(
            vault: vault,
            client: GitHubDeviceFlowClient(clientID: GitHubAppConfig.clientID),
            owner: owner,
            repo: repo,
            branch: branch,
            subdir: subdir
        )
        let vm = GitHubConnectedViewModel.live(
            owner: owner,
            repo: repo,
            branch: branch,
            subdir: subdir,
            credentialProvider: provider,
            vault: vault,
            preferences: container.preferences,
            onDisconnected: {
                connectedViewModel = nil
                connectedOwnerRepo = nil
                container.invalidateGithubCredentialProvider()
                viewModel.disconnect()
            }
        )
        connectedViewModel = vm
        connectedOwnerRepo = key
        return vm
    }

    private func refreshConnectedFromPrefs() {
        guard let vm = connectedViewModel else { return }
        let newBranch = container.preferences.githubBranch ?? ""
        let newSubdir = container.preferences.githubSubdir ?? ""
        let branchChanged = !newBranch.isEmpty && newBranch != vm.branch
        let subdirChanged = newSubdir != vm.subdir
        if branchChanged || subdirChanged {
            connectedViewModel = nil
            connectedOwnerRepo = nil
            container.invalidateGithubCredentialProvider()
        }
    }

    private func onConnectTapped() {
        startDeviceFlowAttempt()
    }

    private func startDeviceFlowAttempt() {
        guard viewModel.canStartAttempt(deviceFlowState: deviceFlow?.state) else {
            return
        }
        let vault = KeychainTokenVault(secrets: container.secrets)
        let client = GitHubDeviceFlowClient(clientID: GitHubAppConfig.clientID)
        let session = DeviceFlowSession.make(vault: vault, client: client)
        let vm = DeviceFlowViewModel.live(session: session)
        let attemptID = viewModel.connect()
        deviceFlow = vm
        viewModel.bindContext(preferences: container.preferences, vault: vault)
        sessionObservationTask?.cancel()
        let destinationVM = viewModel
        sessionObservationTask = Task { @MainActor in
            let stream = await session.observe()
            guard !Task.isCancelled else {
                await session.cancel()
                return
            }
            // Kick off device flow only after observer is registered so we
            // don't miss the `.completed` event in fast-path scenarios.
            vm.begin()
            await destinationVM.observeSession(stream, attemptID: attemptID)
            if (vm.state == .completed || vm.state == .cancelled),
               deviceFlow?.id == vm.id {
                deviceFlow = nil
            }
        }
    }

    private func makeInstallationPickerVM() -> GitHubInstallationPickerViewModel {
        let vault = KeychainTokenVault(secrets: container.secrets)
        let client = GitHubDeviceFlowClient(clientID: GitHubAppConfig.clientID)
        let provider = DeviceFlowCredentialProvider(
            vault: vault,
            client: client,
            owner: "",
            repo: "",
            branch: ""
        )
        let token: @Sendable () async throws -> String = {
            try await provider.accessToken()
        }
        return GitHubInstallationPickerViewModel.live(
            picker: GitHubInstallationPicker(),
            token: token,
            preferences: container.preferences,
            onComplete: { viewModel.pickerCompleted() },
            onDismiss: {
                installationPicker = nil
                if viewModel.state == .pickingRepo {
                    cancelPickerAndClearTokens()
                }
            },
            onSessionExpired: handleSessionExpired
        )
    }

    private func bootstrapState() {
        let owner = container.preferences.githubOwner ?? ""
        let repo = container.preferences.githubRepo ?? ""
        let branch = container.preferences.githubBranch ?? ""
        guard !owner.isEmpty, !repo.isEmpty, !branch.isEmpty else {
            if viewModel.state == .connected {
                viewModel.disconnect()
                connectedViewModel = nil
                connectedOwnerRepo = nil
                container.invalidateGithubCredentialProvider()
            }
            return
        }
        let vault = KeychainTokenVault(secrets: container.secrets)
        Task { @MainActor in
            let stored = try? await vault.load()
            if stored != nil {
                if viewModel.state == .disconnected {
                    viewModel.state = .connected
                }
            } else {
                if viewModel.state == .connected {
                    viewModel.disconnect()
                    connectedViewModel = nil
                    connectedOwnerRepo = nil
                    container.invalidateGithubCredentialProvider()
                }
            }
        }
    }
}
