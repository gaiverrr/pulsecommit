import Foundation
import HealthCore
import Observation
import SwiftUI

@MainActor
@Observable
final class GitHubInstallationPickerViewModel {
    enum Step: Equatable {
        case installations
        case repositories(installationId: Int, account: String)
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    var step: Step = .installations
    var state: LoadState = .idle
    var installations: [GitHubInstallation] = []
    var repositories: [GitHubRepo] = []

    private let loadInstallations: @Sendable () async throws -> [GitHubInstallation]
    private let loadRepositories: @Sendable (Int) async throws -> [GitHubRepo]
    private let persist: @MainActor (GitHubInstallation, GitHubRepo) -> Void
    private let onDismiss: @MainActor () -> Void
    private let onSessionExpired: @MainActor () -> Void

    init(
        loadInstallations: @escaping @Sendable () async throws -> [GitHubInstallation],
        loadRepositories: @escaping @Sendable (Int) async throws -> [GitHubRepo],
        persist: @escaping @MainActor (GitHubInstallation, GitHubRepo) -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) {
        self.loadInstallations = loadInstallations
        self.loadRepositories = loadRepositories
        self.persist = persist
        self.onDismiss = onDismiss
        self.onSessionExpired = onSessionExpired
    }

    func loadInstallationsList() {
        state = .loading
        Task { [loadInstallations] in
            do {
                let result = try await loadInstallations()
                await MainActor.run {
                    self.installations = result
                    self.state = .loaded
                }
            } catch {
                let expired = Self.isSessionExpired(error)
                await MainActor.run {
                    self.state = .failed(Self.message(for: error))
                    if expired {
                        self.onSessionExpired()
                    }
                }
            }
        }
    }

    func selectInstallation(_ installation: GitHubInstallation) {
        step = .repositories(installationId: installation.id, account: installation.account)
        repositories = []
        state = .loading
        Task { [loadRepositories, installation] in
            do {
                let result = try await loadRepositories(installation.id)
                await MainActor.run {
                    self.repositories = result
                    self.state = .loaded
                }
            } catch {
                let expired = Self.isSessionExpired(error)
                await MainActor.run {
                    self.state = .failed(Self.message(for: error))
                    if expired {
                        self.onSessionExpired()
                    }
                }
            }
        }
    }

    private static func isSessionExpired(_ error: Error) -> Bool {
        if let authError = error as? GitHubAuthError, authError == .sessionExpired {
            return true
        }
        if let pickerError = error as? GitHubInstallationPickerError, pickerError == .unauthorized {
            return true
        }
        return false
    }

    func selectRepository(_ repo: GitHubRepo) {
        guard case .repositories(let id, let account) = step else { return }
        let installation = GitHubInstallation(id: id, account: account)
        persist(installation, repo)
        onDismiss()
    }

    func backToInstallations() {
        step = .installations
        state = .loaded
    }

    func cancel() {
        onDismiss()
    }

    static func live(
        picker: GitHubInstallationPicker,
        token: @escaping @Sendable () async throws -> String,
        preferences: PreferencesStore,
        onComplete: @escaping @MainActor () -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onSessionExpired: @escaping @MainActor () -> Void = {}
    ) -> GitHubInstallationPickerViewModel {
        GitHubInstallationPickerViewModel(
            loadInstallations: {
                let t = try await token()
                return try await picker.loadInstallations(token: t)
            },
            loadRepositories: { installationId in
                let t = try await token()
                return try await picker.loadRepositories(installationId: installationId, token: t)
            },
            persist: { installation, repo in
                let parts = repo.fullName.split(separator: "/", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    preferences.githubOwner = parts[0]
                    preferences.githubRepo = parts[1]
                } else {
                    preferences.githubOwner = installation.account
                    preferences.githubRepo = repo.fullName
                }
                preferences.githubInstallationId = installation.id
                preferences.githubBranch = repo.defaultBranch
                onComplete()
            },
            onDismiss: onDismiss,
            onSessionExpired: onSessionExpired
        )
    }

    private static func message(for error: Error) -> String {
        if let e = error as? GitHubInstallationPickerError {
            switch e {
            case .unauthorized: return "Session expired. Reconnect GitHub."
            case .notFound: return "No installations found. Install the Pulse Commit GitHub App first."
            case .network: return "Network error. Check your connection."
            case .unexpected(let code): return "GitHub returned \(code)."
            }
        }
        return "Something went wrong."
    }
}

struct GitHubInstallationPickerSheet: View {
    @Bindable var viewModel: GitHubInstallationPickerViewModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(supertitle)
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                content
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if case .repositories = viewModel.step {
                        Button("Back") { viewModel.backToInstallations() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { viewModel.cancel() }
                }
            }
        }
        .onAppear {
            if case .installations = viewModel.step, viewModel.state == .idle {
                viewModel.loadInstallationsList()
            }
        }
    }

    private var supertitle: String {
        switch viewModel.step {
        case .installations: return "$ pulse installations"
        case .repositories(_, let account): return "$ pulse repos --org=\(account)"
        }
    }

    private var title: String {
        switch viewModel.step {
        case .installations: return "Pick installation"
        case .repositories: return "Pick repository"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.top, 32)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load")
                    .font(.pcBodySemibold)
                    .foregroundStyle(Theme.error)
                Text(message)
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.muted)
            }
            .padding(20)
        case .loaded:
            list
        }
    }

    @ViewBuilder
    private var list: some View {
        switch viewModel.step {
        case .installations:
            if viewModel.installations.isEmpty {
                installInstallationsEmptyState
            } else {
                List(viewModel.installations) { installation in
                    Button {
                        viewModel.selectInstallation(installation)
                    } label: {
                        HStack {
                            Text(installation.account)
                                .font(.pcMonoDetail)
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.dim)
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Theme.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        case .repositories:
            if viewModel.repositories.isEmpty {
                emptyState(
                    title: "No repositories",
                    body: "This installation has no repositories granted to Pulse Commit."
                )
            } else {
                List(viewModel.repositories) { repo in
                    Button {
                        viewModel.selectRepository(repo)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.fullName)
                                    .font(.pcMonoDetail)
                                    .foregroundStyle(Theme.text)
                                Text(repo.defaultBranch)
                                    .font(.pcCaptionMono)
                                    .foregroundStyle(Theme.dim)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(Theme.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func emptyState(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.pcBodySemibold)
                .foregroundStyle(Theme.text)
            Text(body)
                .font(.pcBodySmall)
                .foregroundStyle(Theme.muted)
        }
        .padding(20)
    }

    @ViewBuilder
    private var installInstallationsEmptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Install the app first")
                    .font(.pcBodySemibold)
                    .foregroundStyle(Theme.text)
                Text("Grant Pulse Commit access to the repository you want to commit health data into. You'll pick the exact repo in GitHub's installer.")
                    .font(.pcBodySmall)
                    .foregroundStyle(Theme.muted)
            }

            Button {
                if let url = URL(string: "https://github.com/apps/pulse-commit/installations/new") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Install Pulse Commit on GitHub")
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())

            Button {
                viewModel.loadInstallationsList()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("I've installed it — refresh")
                }
                .font(.pcBodySmall)
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
    }
}
