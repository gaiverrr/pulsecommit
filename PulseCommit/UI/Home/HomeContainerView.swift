import StoreKit
import SwiftUI
import UIKit

struct HomeContainerView: View {
    @EnvironmentObject var container: AppContainer
    @Environment(\.requestReview) private var requestReview
    @Binding var selectedTab: RootTabView.Tab
    @Binding var destinationsPath: [RootTabView.DestinationsRoute]
    @AppStorage("onboarding_completed") private var onboardingCompleted: Bool = false
    @State private var viewModel: HomeViewModel?
    @State private var livePreview: HomeLivePreviewModel?
    @State private var githubConfigured: Bool = false
    @State private var telegramConfigured: Bool = false
    @State private var webhookConfigured: Bool = false
    @State private var healthPermissionNoticeDismissed: Bool = false
    @State private var recentCommits: [HomeView.RecentCommitRow] = []
    @State private var recentCommitsBranchHint: String?
    @State private var latestEntry: HistoryEntrySnapshot?

    var body: some View {
        Group {
            if let viewModel {
                HomeView(
                    viewModel: viewModel,
                    livePreview: livePreview,
                    deviceName: UIDevice.current.name,
                    appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0",
                    timezoneAbbreviation: TimeZone.current.abbreviation() ?? "UTC",
                    recentCommits: recentCommits,
                    recentCommitsBranchHint: recentCommitsBranchHint,
                    healthPermissionRequestCompleted: onboardingCompleted,
                    healthPermissionNoticeDismissed: healthPermissionNoticeDismissed,
                    githubConfigured: githubConfigured,
                    telegramConfigured: telegramConfigured,
                    webhookConfigured: webhookConfigured,
                    onGrantHealth: {
                        Task { @MainActor in
                            do {
                                try await container.healthStore.requestAuthorization(
                                    toShare: nil,
                                    read: HealthAuthorizationView.readTypes()
                                )
                                onboardingCompleted = true
                                refreshState()
                            } catch {
                                // Health data unavailable or request failed —
                                // leave the empty state so the user can retry.
                            }
                        }
                    },
                    onOpenHealthSettings: {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    },
                    onDismissHealthPermissionNotice: {
                        healthPermissionNoticeDismissed = true
                        container.preferences.healthPermissionNoticeDismissed = true
                    },
                    onConnectGitHub: {
                        destinationsPath = [.github]
                        selectedTab = .destinations
                    },
                    onConnectTelegram: {
                        destinationsPath = [.telegram]
                        selectedTab = .destinations
                    },
                    onReconnectGitHub: {
                        destinationsPath = [.github]
                        selectedTab = .destinations
                    },
                    onOpenLatestEntry: {
                        latestEntry = (try? container.history.recentEntries(limit: 1))?.first
                    },
                    onSelectPeriod: { period in
                        viewModel.currentPeriod = period
                        container.preferences.selectedPeriod = period.storageKey
                    }
                )
                .sheet(item: Binding(
                    get: { viewModel.pendingConsentScope },
                    set: { scope in
                        if scope == nil, viewModel.pendingConsentScope != nil {
                            viewModel.declinePendingConsent()
                        }
                    }
                )) { scope in
                    HealthExportConsentSheet(
                        scope: scope,
                        onAllow: { Task { await viewModel.allowPendingConsent() } },
                        onDecline: { viewModel.declinePendingConsent() }
                    )
                    .presentationDetents([.large])
                }
                .sheet(item: $latestEntry) { entry in
                    NavigationStack { HistoryDetailView(entry: entry) }
                }
                .onChange(of: viewModel.phase) { _, newPhase in
                    refreshState()
                    if case .done = newPhase, container.preferences.recordSuccessfulManualExport() {
                        requestReview()
                    }
                }
            } else {
                Theme.bg.ignoresSafeArea()
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = HomeViewModel(container: container)
            }
            if livePreview == nil {
                livePreview = HomeLivePreviewModel(registry: container.registry)
            }
            refreshState()
        }
    }

    private func refreshState() {
        Task { @MainActor in
            await refreshConfigured()
        }
        healthPermissionNoticeDismissed = container.preferences.healthPermissionNoticeDismissed
        recentCommits = loadRecentCommits()
        recentCommitsBranchHint = buildBranchHint()
        viewModel?.refreshSessionExpired()
        // Pull persisted period in case it was changed externally (e.g. from
        // an App Intent in a future build). On first launch this also seeds
        // the view-model from prefs.
        if let viewModel {
            let persisted = HomeViewModel.Period(storageKey: container.preferences.selectedPeriod)
            if viewModel.currentPeriod != persisted {
                viewModel.currentPeriod = persisted
            }
        }
    }

    private func refreshConfigured() async {
        // Single source of truth shared with the orchestrator factory and
        // Shortcuts (`IntentRunner`): a destination counts as configured only
        // when its export toggle is on AND its credentials are present.
        let ids = await IntentRunner.configuredSinkIds(container)
        githubConfigured = ids.contains("github")
        telegramConfigured = ids.contains("telegram")
        webhookConfigured = ids.contains(WebhookDestinationSink.sinkID)
    }

    private func loadRecentCommits() -> [HomeView.RecentCommitRow] {
        let entries = (try? container.history.recentEntries(limit: 4)) ?? []
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        return entries.map { entry in
            let shortSha = entry.githubCommitSha.map { String($0.prefix(7)) }
            let dateLabel = dateFormatter.string(from: entry.startedAt)
            let timeAgo = relative.localizedString(for: entry.startedAt, relativeTo: Date())
            let summary: String
            if entry.status == .success {
                let days = entry.daysCovered.count
                summary = days == 1 ? "exported 1 day" : "exported \(days) days"
            } else {
                let raw = entry.displayErrorMessage ?? "failed"
                summary = String(raw.prefix(60))
            }
            return HomeView.RecentCommitRow(
                id: entry.id,
                shortSha: shortSha,
                dateLabel: dateLabel,
                timeAgo: timeAgo,
                summary: summary,
                ok: entry.status == .success
            )
        }
    }

    private func buildBranchHint() -> String? {
        let prefs = container.preferences
        let branch = (prefs.githubBranch ?? "").trimmingCharacters(in: .whitespaces)
        let owner = (prefs.githubOwner ?? "").trimmingCharacters(in: .whitespaces)
        let repo = (prefs.githubRepo ?? "").trimmingCharacters(in: .whitespaces)
        guard !branch.isEmpty, !owner.isEmpty, !repo.isEmpty else { return nil }
        return "\(branch) · \(owner)/\(repo)"
    }
}
