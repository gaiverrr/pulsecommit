import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var container: AppContainer
    var onBackToHome: () -> Void = {}
    @State private var navigationPath = NavigationPath()
    @State private var githubSummary: String = "Not set"
    @State private var telegramSummary: String = "Not set"
    @State private var showResetConfirm: Bool = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    general
                    destinations
                    privacy
                    about
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { await refresh() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            Text("Settings")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)
            Text("v\(Self.marketingVersion)")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
        }
        .padding(.top, 8)
    }

    private static let marketingVersion =
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"

    private static let buildNumber =
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""

    static func versionLabel(marketing: String, build: String) -> String {
        build.isEmpty ? marketing : "\(marketing) (\(build))"
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "GENERAL")
            PCCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        HeartRateZonesView().environmentObject(container)
                    } label: {
                        settingsRow(title: "Heart Rate Zones", value: "Custom boundaries", locked: false, accent: false)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.divider)
                    NavigationLink {
                        ShortcutsHelpView()
                    } label: {
                        settingsRow(title: "Schedule via", value: "Shortcuts", locked: false, accent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "DESTINATIONS")
            PCCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        TelegramDestinationView(onBackToHome: {
                            navigationPath = NavigationPath()
                            onBackToHome()
                        }).environmentObject(container)
                    } label: {
                        settingsRow(title: "Telegram", value: telegramSummary, locked: false, accent: true)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "PRIVACY")
            PCCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        settingsRow(title: "What we collect", value: "Nothing", locked: false, accent: false, valueColor: Theme.success)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.divider)
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        settingsRow(title: "Where data goes", value: "Your destinations only", locked: false, accent: false)
                    }
                    .buttonStyle(.plain)
                    Divider().background(Theme.divider)
                    Button {
                        showResetConfirm = true
                    } label: {
                        settingsRow(
                            title: "Reset all data",
                            value: "Wipe",
                            locked: false,
                            accent: false,
                            valueColor: Theme.error,
                            titleColor: Theme.error
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .confirmationDialog(
            "Wipe all stored tokens, history, and preferences?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset all data", role: .destructive) {
                Task { await performReset() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @MainActor
    private func performReset() async {
        container.prepareForReset()
        let secrets = container.secrets
        for key in AppContainer.resettableSecretKeys {
            try? await secrets.set(nil, for: key)
        }
        container.preferences.reset()
        container.consentStore.reset()
        _ = await container.automaticWorkoutAttempts.reset()
        try? container.history.deleteAll()
        await refresh()
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "ABOUT")
            PCCard(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        ChangelogView()
                    } label: {
                        settingsRow(
                            title: "Version",
                            value: Self.versionLabel(marketing: Self.marketingVersion, build: Self.buildNumber),
                            locked: false,
                            accent: false
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens the changelog"))
                    Divider().background(Theme.divider)
                    externalRow(title: "Website", value: "pulsecommit.app", url: AboutLinks.website)
                    Divider().background(Theme.divider)
                    externalRow(title: "Source code", value: "gaiverrr/pulsecommit", url: AboutLinks.source)
                    Divider().background(Theme.divider)
                    externalRow(title: "Contact", value: "hi@pulsecommit.app", url: AboutLinks.contact)
                    Divider().background(Theme.divider)
                    NavigationLink {
                        LicensesView()
                    } label: {
                        settingsRow(title: "Licenses", value: "MIT", locked: false, accent: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footer: some View {
        Text("⌘ Made with care in Lisbon, 2026")
            .font(.pcCaptionMono)
            .foregroundStyle(Theme.faint)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 12)
    }

    private func externalRow(title: String, value: String, url: URL) -> some View {
        Link(destination: url) {
            settingsRow(
                title: title,
                value: value,
                locked: false,
                accent: false,
                trailingSymbol: "arrow.up.right"
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(url.scheme == "mailto" ? "Opens Mail" : "Opens in Safari"))
    }

    private func settingsRow(title: String, value: String, locked: Bool, accent: Bool, valueColor: Color? = nil, titleColor: Color? = nil, trailingSymbol: String = "chevron.right") -> some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.pcBodyLarge)
                .foregroundStyle(titleColor ?? Theme.text)
            Spacer()
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.dim)
            }
            Text(value)
                .font(accent ? .pcMonoDetail : .pcBodySmall)
                .foregroundStyle(valueColor ?? (accent ? Theme.accent : Theme.muted))
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: trailingSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    private func refresh() async {
        let owner = container.preferences.githubOwner ?? ""
        let repo = container.preferences.githubRepo ?? ""
        if !owner.isEmpty && !repo.isEmpty {
            githubSummary = "\(owner)/\(repo)"
        } else {
            githubSummary = "Not set"
        }
        let chat = (try? await container.secrets.get("tg_chat_id")) ?? nil ?? ""
        let verbosity = container.preferences.telegramVerbosity
        if !chat.isEmpty {
            telegramSummary = "\(chat) · \(verbosity)"
        } else {
            telegramSummary = "Not set"
        }
    }
}
