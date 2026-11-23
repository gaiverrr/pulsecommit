import Foundation
import Observation
import SwiftUI
import HealthCore

@MainActor
@Observable
final class GitHubConnectedViewModel {
    enum TestResult: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    var owner: String
    var repo: String
    var branch: String
    var subdir: String
    var testResult: TestResult = .idle
    var showDisconnectConfirm: Bool = false

    private let testConnectionAction: @Sendable (_ owner: String, _ repo: String) async -> TestResult
    private let disconnectAction: @Sendable () async -> Void
    private let onDisconnected: @MainActor () -> Void

    init(
        owner: String,
        repo: String,
        branch: String,
        subdir: String,
        testConnection: @escaping @Sendable (_ owner: String, _ repo: String) async -> TestResult,
        disconnect: @escaping @Sendable () async -> Void,
        onDisconnected: @escaping @MainActor () -> Void
    ) {
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.subdir = subdir
        self.testConnectionAction = testConnection
        self.disconnectAction = disconnect
        self.onDisconnected = onDisconnected
    }

    func runTestConnection() {
        testResult = .running
        Task { [testConnectionAction, owner, repo] in
            let result = await testConnectionAction(owner, repo)
            await MainActor.run {
                self.testResult = result
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if self.testResult == result {
                    self.testResult = .idle
                }
            }
        }
    }

    func requestDisconnect() {
        showDisconnectConfirm = true
    }

    func confirmDisconnect() {
        showDisconnectConfirm = false
        Task { [disconnectAction] in
            await disconnectAction()
            await MainActor.run {
                self.onDisconnected()
            }
        }
    }

    func cancelDisconnect() {
        showDisconnectConfirm = false
    }

    static func live(
        owner: String,
        repo: String,
        branch: String,
        subdir: String,
        credentialProvider: any GitHubCredentialProvider,
        vault: any TokenVault,
        preferences: PreferencesStore,
        session: URLSession = EphemeralAPISession.shared,
        onDisconnected: @escaping @MainActor () -> Void
    ) -> GitHubConnectedViewModel {
        let clearSession: @Sendable () async -> Void = {
            await credentialProvider.invalidateSession()
            try? await vault.clear()
            await MainActor.run {
                preferences.githubOwner = nil
                preferences.githubRepo = nil
                preferences.githubBranch = nil
                preferences.githubSubdir = nil
                preferences.githubInstallationId = nil
            }
        }
        return GitHubConnectedViewModel(
            owner: owner,
            repo: repo,
            branch: branch,
            subdir: subdir,
            testConnection: { owner, repo in
                let result = await Self.performTestConnection(
                    owner: owner,
                    repo: repo,
                    credentialProvider: credentialProvider,
                    session: session
                )
                if case .sessionExpired = result {
                    await clearSession()
                    await MainActor.run { onDisconnected() }
                    return .failure("Session expired. Reconnect GitHub.")
                }
                if case .result(let r) = result { return r }
                return .failure("Unknown error")
            },
            disconnect: clearSession,
            onDisconnected: onDisconnected
        )
    }

    private enum TestConnectionOutcome {
        case result(TestResult)
        case sessionExpired
    }

    private static func performTestConnection(
        owner: String,
        repo: String,
        credentialProvider: any GitHubCredentialProvider,
        session: URLSession
    ) async -> TestConnectionOutcome {
        do {
            let token = try await credentialProvider.accessToken()
            let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .result(.failure("Invalid response"))
            }
            if http.statusCode == 401 {
                return .sessionExpired
            }
            if (200..<300).contains(http.statusCode) {
                return .result(.success)
            }
            return .result(.failure("HTTP \(http.statusCode)"))
        } catch GitHubAuthError.sessionExpired {
            return .sessionExpired
        } catch {
            return .result(.failure(gitHubUserFacingMessage(error)))
        }
    }
}

struct GitHubConnectedView: View {
    @Bindable var viewModel: GitHubConnectedViewModel
    var onEditBranch: () -> Void = {}
    var onEditSubdir: () -> Void = {}
    var consentScope: HealthExportConsentScope?
    var consentStore: HealthExportConsentStore?
    var onAllowConsent: (HealthExportConsentScope) async -> Bool = { _ in false }
    @State private var presentedConsent: HealthExportConsentScope?
    @State private var consentRefresh = 0

    static func previewTree(owner: String, repo: String, branch: String, subdir: String) -> String {
        let root = subdir.isEmpty ? "\(owner)/\(repo)@\(branch)" : "\(owner)/\(repo)@\(branch):\(subdir)"
        return """
        \(root)
        └── 2026-05-15/
            ├── summary.json
            ├── summary.md
            ├── samples/
            │   └── steps.json
            └── workouts/
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("$ pulse status")
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.dim)
                    .padding(.top, 8)

                HStack(spacing: 8) {
                    PCStatusDot(color: Theme.success)
                    PCPill(
                        text: "● CONNECTED",
                        monospaced: true,
                        foreground: Theme.success,
                        background: Theme.success.opacity(0.12)
                    )
                    Spacer()
                }

                PCCard {
                    VStack(alignment: .leading, spacing: 12) {
                        PCSectionHeader(title: "REPOSITORY")
                        Text("\(viewModel.owner)/\(viewModel.repo)")
                            .font(.system(size: 18, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                        Divider().background(Theme.divider)
                        editRow(
                            label: "Branch",
                            value: viewModel.branch.isEmpty ? "—" : viewModel.branch,
                            action: onEditBranch
                        )
                        Divider().background(Theme.divider)
                        editRow(
                            label: "Subdir",
                            value: viewModel.subdir.isEmpty ? "(root)" : viewModel.subdir,
                            action: onEditSubdir
                        )
                    }
                }

                if let consentScope, let consentStore {
                    Button {
                        presentedConsent = consentScope
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Export consent")
                                    .font(.pcBody)
                                    .foregroundStyle(Theme.text)
                                Text(consentStore.hasCurrentConsent(for: consentScope) ? "CURRENT" : "REVIEW REQUIRED")
                                    .font(.pcCaptionMono)
                                    .foregroundStyle(consentStore.hasCurrentConsent(for: consentScope) ? Theme.success : Theme.warn)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.faint)
                        }
                        .padding(14)
                        .background(PCCardBackground())
                    }
                    .buttonStyle(.plain)
                    .id(consentRefresh)
                }

                PCSectionHeader(title: "PREVIEW · NEXT COMMIT")
                PCCodeBlock(content: Self.previewTree(
                    owner: viewModel.owner,
                    repo: viewModel.repo,
                    branch: viewModel.branch,
                    subdir: viewModel.subdir
                ))

                testConnectionButton

                if case .success = viewModel.testResult {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.success)
                        Text("Connection OK")
                            .font(.pcBodySmall)
                            .foregroundStyle(Theme.success)
                    }
                }
                if case .failure(let message) = viewModel.testResult {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.error)
                        Text(message)
                            .font(.pcBodySmall)
                            .foregroundStyle(Theme.error)
                    }
                }

                Button(role: .destructive, action: viewModel.requestDisconnect) {
                    Text("Disconnect GitHub")
                        .font(.pcBody)
                        .foregroundStyle(Theme.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .confirmationDialog(
            "Disconnect GitHub?",
            isPresented: $viewModel.showDisconnectConfirm,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                viewModel.confirmDisconnect()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelDisconnect()
            }
        } message: {
            Text("Tokens and repo settings will be cleared from this device.")
        }
        .sheet(item: $presentedConsent) { scope in
            HealthExportConsentSheet(
                scope: scope,
                onAllow: {
                    Task { @MainActor in
                        if await onAllowConsent(scope) { consentRefresh += 1 }
                        presentedConsent = nil
                    }
                },
                onDecline: { presentedConsent = nil }
            )
        }
    }

    private var testConnectionButton: some View {
        Button(action: viewModel.runTestConnection) {
            HStack(spacing: 8) {
                if viewModel.testResult == .running {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "bolt.fill")
                }
                Text(viewModel.testResult == .running ? "Testing…" : "Test connection")
            }
            .font(.pcBody)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.testResult == .running)
    }

    private func editRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.pcLabel)
                    .tracking(1.2)
                    .foregroundStyle(Theme.muted)
                Text(value)
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            Button(action: action) {
                Text("Edit")
                    .font(.pcBodySmall)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct PCCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            )
    }
}
