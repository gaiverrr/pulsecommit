import SwiftUI
import UIKit
import AuthenticationServices

struct GitHubDeviceCodeSheet: View {
    @Bindable var viewModel: DeviceFlowViewModel
    let onDismiss: () -> Void
    let onRetry: () -> Void

    @State private var showCopied: Bool = false
    @State private var authSession: ASWebAuthenticationSession?
    @State private var browserErrorMessage: String?

    static func formatUserCode(_ raw: String) -> String {
        guard raw.count == 8 else { return raw }
        let mid = raw.index(raw.startIndex, offsetBy: 4)
        return "\(raw[raw.startIndex..<mid])-\(raw[mid..<raw.endIndex])"
    }

    static func copyToPasteboard(_ code: String) {
        UIPasteboard.general.string = code
    }

    static func shouldDismiss(for state: DeviceFlowViewModel.DisplayState) -> Bool {
        switch state {
        case .completed, .cancelled:
            return true
        case .idle, .awaitingApproval, .approving, .failed:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("$ pulse approve")
                .font(.pcMonoDetail)
                .foregroundStyle(Theme.dim)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("ENTER THIS CODE IN GITHUB")
                    .font(.pcLabel)
                    .tracking(1.5)
                    .foregroundStyle(Theme.muted)

                Button(action: copyCurrentCode) {
                    Text(displayCode)
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.elevated)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Theme.hairline, lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!hasUsableCode)
                .opacity(hasUsableCode ? 1 : 0.45)
                .overlay(alignment: .topTrailing) {
                    if showCopied {
                        Text("Copied ✓")
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.accentSoft)
                            )
                            .padding(8)
                            .transition(.opacity)
                    }
                }

                Text("> tap code to copy")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.faint)
                    .opacity(hasUsableCode ? 1 : 0)
            }

            if viewModel.state == .failed {
                Button(action: onRetry) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        Text("Try again")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
            } else {
                Button(action: openInBrowser) {
                    HStack(spacing: 8) {
                        Image(systemName: "safari")
                        Text("Open GitHub")
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(!hasUsableCode)
                .opacity(hasUsableCode ? 1 : 0.45)
            }

            HStack(spacing: 10) {
                PCStatusDot(color: statusColor, pulsing: isWorking)
                Text(statusLabel)
                    .font(.pcBody)
                    .foregroundStyle(Theme.muted)
            }

            if let message = viewModel.errorMessage ?? browserErrorMessage {
                Text(message)
                    .font(.pcBodySmall)
                    .foregroundStyle(Theme.error)
            }

            Spacer(minLength: 0)

            Button(action: { viewModel.cancel() }) {
                Text("Cancel")
                    .font(.pcBody)
                    .foregroundStyle(Theme.muted)
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
        }
        .padding(20)
        .background(Theme.bg.ignoresSafeArea())
        .onChange(of: viewModel.state) { _, newState in
            if Self.shouldDismiss(for: newState) {
                onDismiss()
            }
        }
        .onDisappear {
            authSession?.cancel()
            authSession = nil
        }
    }

    private var displayCode: String {
        guard let code = viewModel.userCode else { return "————————" }
        return Self.formatUserCode(code)
    }

    private var hasUsableCode: Bool {
        guard viewModel.userCode != nil, viewModel.verificationURI != nil else {
            return false
        }
        return viewModel.state == .awaitingApproval || viewModel.state == .approving
    }

    private var isWorking: Bool {
        switch viewModel.state {
        case .idle, .awaitingApproval, .approving:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    private var statusColor: Color {
        switch viewModel.state {
        case .failed, .cancelled:
            return Theme.error
        case .completed:
            return Theme.success
        case .idle, .awaitingApproval, .approving:
            return Theme.accent
        }
    }

    private var statusLabel: String {
        switch viewModel.state {
        case .awaitingApproval, .approving:
            return "Waiting for approval…"
        case .idle:
            return "Starting…"
        case .completed:
            return "Connected"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        }
    }

    private func copyCurrentCode() {
        guard let code = viewModel.userCode else { return }
        Self.copyToPasteboard(Self.formatUserCode(code))
        withAnimation(.easeInOut(duration: 0.15)) { showCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
            }
        }
    }

    private func openInBrowser() {
        guard let url = viewModel.verificationURI else { return }
        browserErrorMessage = nil
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: nil
        ) { _, _ in }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = AuthPresentationContextProvider.shared
        authSession = session
        if !session.start() {
            authSession = nil
            browserErrorMessage = "Couldn't open GitHub. Try again."
        }
    }
}

private final class AuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AuthPresentationContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}
