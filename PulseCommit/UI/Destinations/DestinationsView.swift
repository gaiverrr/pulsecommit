import SwiftUI

struct DestinationsView: View {
    @EnvironmentObject var container: AppContainer
    @Binding var path: [RootTabView.DestinationsRoute]
    var onBackToHome: () -> Void = {}
    @State private var telegramConfigured: Bool = false
    @State private var githubConfigured: Bool = false
    @State private var githubExportEnabled: Bool = true
    @State private var telegramExportEnabled: Bool = true
    @State private var telegramChatId: String = ""
    @State private var webhookHost: String?
    @State private var webhookReady: Bool = false
    @State private var webhookExportEnabled: Bool = true

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    PCCard(padding: 0) {
                        VStack(spacing: 0) {
                            NavigationLink(value: RootTabView.DestinationsRoute.github) {
                                row(
                                    icon: .asset("github"),
                                    title: "GitHub",
                                    subtitle: githubSubtitle,
                                    statusText: githubConfigured ? "● CONNECTED" : "● NOT SET",
                                    statusColor: githubConfigured ? Theme.success : Theme.dim,
                                    configured: githubConfigured,
                                    enabled: $githubExportEnabled,
                                    onToggle: setGithubEnabled,
                                    toggleAccessibilityId: "destinations.github.toggle"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().background(Theme.divider)

                            NavigationLink(value: RootTabView.DestinationsRoute.telegram) {
                                row(
                                    icon: .system("paperplane.fill"),
                                    title: "Telegram",
                                    subtitle: telegramSubtitle,
                                    statusText: telegramConfigured ? "● CONNECTED" : "● NOT SET",
                                    statusColor: telegramConfigured ? Theme.success : Theme.dim,
                                    configured: telegramConfigured,
                                    enabled: $telegramExportEnabled,
                                    onToggle: setTelegramEnabled,
                                    toggleAccessibilityId: "destinations.telegram.toggle"
                                )
                            }
                            .buttonStyle(.plain)

                            Divider().background(Theme.divider)

                            NavigationLink(value: RootTabView.DestinationsRoute.webhook) {
                                row(
                                    icon: .system("arrow.up.forward.app"),
                                    title: "Webhook",
                                    badge: "NEW",
                                    subtitle: webhookHost ?? "POST JSON to your own HTTPS endpoint",
                                    statusText: webhookStatusText,
                                    statusColor: webhookStatusColor,
                                    configured: webhookHost != nil,
                                    enabled: $webhookExportEnabled,
                                    onToggle: setWebhookEnabled,
                                    toggleAccessibilityId: "destinations.webhook.toggle"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RootTabView.DestinationsRoute.self) { route in
                switch route {
                case .github:
                    GitHubDestinationView()
                case .telegram:
                    TelegramDestinationView(onBackToHome: onBackToHome)
                case .webhook:
                    WebhookDestinationView()
                }
            }
            .onAppear(perform: refresh)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ pulse remote -v")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
            Text("Destinations")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var githubSubtitle: String {
        guard githubConfigured else { return "Atomic daily commit" }
        let owner = container.preferences.githubOwner ?? ""
        let repo = container.preferences.githubRepo ?? ""
        let branch = container.preferences.githubBranch ?? "main"
        return "\(owner)/\(repo) · \(branch)"
    }

    private var telegramSubtitle: String {
        guard telegramConfigured else { return "MarkdownV2 + ZIP" }
        let verbosity = container.preferences.telegramVerbosity
        return "chat \(telegramChatId) · \(verbosity)"
    }

    private var webhookStatusText: String {
        guard webhookHost != nil else { return "● NOT SET" }
        return webhookReady ? "● CONNECTED" : "● REVIEW"
    }

    private var webhookStatusColor: Color {
        guard webhookHost != nil else { return Theme.dim }
        return webhookReady ? Theme.success : Theme.warn
    }

    static func toggleBinding(
        configured: Bool,
        enabled: Binding<Bool>,
        onToggle: @escaping (Bool) -> Void
    ) -> Binding<Bool> {
        Binding(
            get: { configured && enabled.wrappedValue },
            set: { newValue in
                enabled.wrappedValue = newValue
                onToggle(newValue)
            }
        )
    }

    private enum RowIcon {
        case system(String)
        case asset(String)
    }

    private func row(
        icon: RowIcon,
        title: String,
        badge: String? = nil,
        subtitle: String,
        statusText: String,
        statusColor: Color,
        configured: Bool,
        enabled: Binding<Bool>,
        onToggle: @escaping (Bool) -> Void,
        toggleAccessibilityId: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.elevated)
                    .frame(width: 36, height: 36)
                Group {
                    switch icon {
                    case .system(let name):
                        Image(systemName: name)
                            .font(.system(size: 16))
                    case .asset(let name):
                        Image(name)
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 18, height: 18)
                    }
                }
                .foregroundStyle(Theme.text)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.pcBodyLarge)
                        .foregroundStyle(Theme.text)
                    if let badge {
                        PCPill(text: badge, foreground: Color.black, background: Theme.accent)
                    }
                }
                Text(subtitle)
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
                if !configured {
                    Text("> Configure first")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(statusText)
                    .font(.pcLabel)
                    .tracking(1.2)
                    .foregroundStyle(statusColor)
                PCToggle(accessibilityLabel: "\(title) export", isOn: Self.toggleBinding(
                    configured: configured,
                    enabled: enabled,
                    onToggle: onToggle
                ))
                .disabled(!configured)
                .opacity(configured ? 1 : 0.5)
                .allowsHitTesting(true)
                .accessibilityIdentifier(toggleAccessibilityId)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func setGithubEnabled(_ value: Bool) {
        container.preferences.githubExportEnabled = value
    }

    private func setTelegramEnabled(_ value: Bool) {
        container.preferences.telegramExportEnabled = value
    }

    private func setWebhookEnabled(_ value: Bool) {
        container.preferences.webhookExportEnabled = value
        Task { @MainActor in webhookReady = await container.webhookExportIsReady() }
    }

    private func refresh() {
        githubExportEnabled = container.preferences.githubExportEnabled
        telegramExportEnabled = container.preferences.telegramExportEnabled
        webhookExportEnabled = container.preferences.webhookExportEnabled
        Task { @MainActor in
            let bot = (try? await container.secrets.get("tg_bot_token")) ?? nil ?? ""
            let chat = (try? await container.secrets.get("tg_chat_id")) ?? nil ?? ""
            let hasTokens = await KeychainTokenVault.hasStoredTokens(in: container.secrets)
            telegramConfigured = !bot.isEmpty && !chat.isEmpty
            telegramChatId = chat
            let owner = container.preferences.githubOwner ?? ""
            let repo = container.preferences.githubRepo ?? ""
            let branch = container.preferences.githubBranch ?? ""
            githubConfigured = !owner.isEmpty && !repo.isEmpty && !branch.isEmpty && hasTokens
            webhookHost = await container.currentWebhookConfiguration()?.host
            webhookReady = await container.webhookExportIsReady()
        }
    }
}
