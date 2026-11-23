import Foundation
import HealthCore
import Observation

struct HomeHistorySnapshot: Sendable {
    var status: HistoryEntry.Status
    var errorMessage: String?
    var errorKind: String?
}

@MainActor
@Observable
final class HomeViewModel {
    enum Phase: Equatable {
        case idle
        case running
        case done(at: Date)
        case error(reason: String)
    }

    // The set of period choices a user can pick from the Home big-button
    // chip-row Menu. The legacy `SmartMode` (auto today/yesterday by AM/PM)
    // is gone — period is now user-set and persisted.
    enum Period: Equatable {
        case today
        case yesterday
        case last7Days
        case last30Days
        case custom

        static let storageDefault: String = "today"

        init(storageKey: String) {
            switch storageKey {
            case "yesterday": self = .yesterday
            case "last_7_days": self = .last7Days
            case "last_30_days": self = .last30Days
            // "custom" was persistable before the date-picker shipped;
            // restore stale values to an honest, pickable period.
            default: self = .today
            }
        }

        var storageKey: String {
            switch self {
            case .today: return "today"
            case .yesterday: return "yesterday"
            case .last7Days: return "last_7_days"
            case .last30Days: return "last_30_days"
            case .custom: return "custom"
            }
        }

        var exportMode: ExportRequest.Mode {
            switch self {
            case .today: return .todayLive
            case .yesterday: return .lastDayOnly
            case .last7Days: return .lastNDays(7)
            case .last30Days: return .lastNDays(30)
            // Custom range without a concrete picker yet — fall back to
            // todayLive. The UI does not offer `.custom` until a
            // date-picker sheet exists, so this path is unreachable in shipping
            // builds but keeps the type total.
            case .custom: return .todayLive
            }
        }
    }

    var phase: Phase = .idle
    var sessionExpired: Bool = false
    var pendingConsentScope: HealthExportConsentScope?
    var currentPeriod: Period = .today
    // Split storage so SwiftUI can fade only the category label while the
    // counter updates in place.
    var stagePrefix: String = ""
    var stageLabel: String? = nil
    var stageCounter: String? = nil

    // Backward-compatible concatenation; used by accessibility hint and
    // existing test fixtures. Returns "" when no stage is active (instead
    // of nil) so callers can treat it as a stable string. View should
    // branch on phase, not on this returning empty.
    var currentStage: String {
        let labelPart = stageLabel ?? ""
        let counterPart = stageCounter.map { " \($0)" } ?? ""
        return "\(stagePrefix)\(labelPart)\(counterPart)"
    }

    private let runRequest: @MainActor (ExportRequest, RunProgressHandler?) async -> Orchestrator.RunResult
    private let enabledCategoryIdsProvider: @MainActor () -> Set<String>
    private let enabledSinkIdsProvider: @MainActor () async -> Set<String>
    private let recentHistoryProvider: @MainActor () -> [HomeHistorySnapshot]
    private let consentPreflight: @MainActor (ExportRequest) async -> [HealthExportConsentScope]
    private let acceptConsent: @MainActor (HealthExportConsentScope) async -> Bool
    private let clock: @MainActor () -> Date
    private let calendar: Calendar
    private var pendingSinkOverride: Set<String>?
    private var pendingModeOverride: ExportRequest.Mode?

    init(
        runRequest: @escaping @MainActor (ExportRequest, RunProgressHandler?) async -> Orchestrator.RunResult,
        enabledCategoryIds: @escaping @MainActor () -> Set<String>,
        enabledSinkIds: @escaping @MainActor () async -> Set<String>,
        recentHistory: @escaping @MainActor () -> [HomeHistorySnapshot] = { [] },
        consentPreflight: @escaping @MainActor (ExportRequest) async -> [HealthExportConsentScope] = { _ in [] },
        acceptConsent: @escaping @MainActor (HealthExportConsentScope) async -> Bool = { _ in true },
        clock: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .current,
        initialPeriod: Period = .today
    ) {
        self.runRequest = runRequest
        self.enabledCategoryIdsProvider = enabledCategoryIds
        self.enabledSinkIdsProvider = enabledSinkIds
        self.recentHistoryProvider = recentHistory
        self.consentPreflight = consentPreflight
        self.acceptConsent = acceptConsent
        self.clock = clock
        self.calendar = calendar
        self.currentPeriod = initialPeriod
    }

    convenience init(container: AppContainer) {
        self.init(
            runRequest: { request, progress in
                let orchestrator = await container.orchestratorFactory()
                return await orchestrator.runResult(request, progress: progress)
            },
            enabledCategoryIds: { container.preferences.enabledCategoryIds },
            enabledSinkIds: {
                var ids = Set<String>()
                let secrets = container.secrets
                let prefs = container.preferences
                if prefs.githubExportEnabled,
                   let owner = prefs.githubOwner,
                   let repo = prefs.githubRepo,
                   let branch = prefs.githubBranch,
                   !owner.isEmpty, !repo.isEmpty, !branch.isEmpty,
                   await KeychainTokenVault.hasStoredTokens(in: secrets) {
                    ids.insert("github")
                }
                if prefs.telegramExportEnabled,
                   let bot = (try? await secrets.get("tg_bot_token")) ?? nil,
                   let chat = (try? await secrets.get("tg_chat_id")) ?? nil,
                   !bot.isEmpty, !chat.isEmpty {
                    ids.insert("telegram")
                }
                return ids
            },
            recentHistory: {
                let entries = (try? container.history.recentEntries(limit: 20)) ?? []
                return entries.map {
                    HomeHistorySnapshot(
                        status: $0.status,
                        errorMessage: $0.errorMessage,
                        errorKind: $0.errorKind
                    )
                }
            },
            consentPreflight: { request in
                let orchestrator = await container.orchestratorFactory()
                return await orchestrator.missingConsentScopes(for: request)
            },
            acceptConsent: { scope in
                await container.acceptConsentIfCurrent(scope)
            },
            initialPeriod: Period(storageKey: container.preferences.selectedPeriod)
        )
    }

    func refreshSessionExpired() {
        let recent = recentHistoryProvider()
        for entry in recent {
            if entry.status == .success {
                sessionExpired = false
                return
            }
            if entry.status == .failed, entry.errorKind == HistoryErrorKind.sessionExpired {
                sessionExpired = true
                return
            }
        }
        sessionExpired = false
    }

    func runExport(
        sinkOverride: Set<String>? = nil,
        modeOverride: ExportRequest.Mode? = nil
    ) async {
        guard phase != .running else { return }
        let baseSinks = await enabledSinkIdsProvider()
        let sinks = sinkOverride.map { $0.intersection(baseSinks) } ?? baseSinks
        let resolvedMode: ExportRequest.Mode = modeOverride ?? currentPeriod.exportMode
        let request = ExportRequest(
            mode: resolvedMode,
            enabledCategoryIds: enabledCategoryIdsProvider(),
            enabledSinkIds: sinks
        )
        let missing = await consentPreflight(request)
        if let first = missing.first {
            pendingSinkOverride = sinkOverride
            pendingModeOverride = modeOverride
            pendingConsentScope = first
            phase = .idle
            return
        }
        pendingConsentScope = nil
        phase = .running
        stagePrefix = ""
        stageLabel = nil
        stageCounter = nil
        // Hop progress events from the orchestrator's actor back to MainActor
        // so the @Observable update lands on the UI thread.
        let handler: RunProgressHandler = { [weak self] progress in
            await MainActor.run { [weak self] in
                self?.updateStage(progress)
            }
        }
        let result = await runRequest(request, handler)
        switch result.status {
        case .success:
            phase = .done(at: clock())
        case .failed, .paywalled:
            if let coverageError = result.coverageError {
                phase = .error(reason: coverageError.userMessage)
            } else if recentHistoryProvider().first?.errorKind == HistoryErrorKind.consentRequired,
               let first = await consentPreflight(request).first {
                pendingConsentScope = first
                phase = .idle
            } else {
                phase = .error(reason: "export failed")
            }
        }
        stagePrefix = ""
        stageLabel = nil
        stageCounter = nil
        refreshSessionExpired()
    }

    func allowPendingConsent() async {
        guard let scope = pendingConsentScope else { return }
        let sinkOverride = pendingSinkOverride
        let modeOverride = pendingModeOverride
        pendingConsentScope = nil
        guard await acceptConsent(scope) else {
            await runExport(sinkOverride: sinkOverride, modeOverride: modeOverride)
            return
        }
        await runExport(sinkOverride: sinkOverride, modeOverride: modeOverride)
    }

    func declinePendingConsent() {
        pendingConsentScope = nil
        pendingSinkOverride = nil
        pendingModeOverride = nil
        phase = .idle
    }

    // Maps a HealthCore category id to a human-readable phrase shown in the
    // live progress line. English-only per CLAUDE.md "Out of scope".
    // Lab categories (blood_oxygen, respiratory_rate, mindful_minutes) are
    // listed preemptively — they're not registered in CategoryRegistry in
    // v1.0, but the entries cost nothing and protect against future drift.
    func friendlyName(for categoryID: String) -> String {
        switch categoryID {
        case "steps": return "steps"
        case "distance_walking_running": return "distance"
        case "active_energy": return "active energy"
        case "activity_rings": return "activity rings"
        case "heart_rate": return "heart rate"
        case "resting_heart_rate": return "resting heart rate"
        case "hrv_sdnn": return "HRV"
        case "vo2_max": return "VO2 max"
        case "sleep": return "sleep"
        case "body_mass": return "body mass"
        case "state_of_mind": return "state of mind"
        case "workouts": return "workouts"
        case "nutrition": return "nutrition"
        case "hydration": return "hydration"
        case "blood_oxygen": return "blood oxygen"
        case "respiratory_rate": return "respiratory rate"
        case "mindful_minutes": return "mindful minutes"
        default: return categoryID
        }
    }

    func updateStage(_ progress: RunProgress) {
        switch progress {
        case .fetching:
            stagePrefix = "> starting export…"
            stageLabel = nil
            stageCounter = nil

        case .readingSummary(let categoryID, let completed, let total):
            stagePrefix = "> totals · "
            stageLabel = friendlyName(for: categoryID)
            stageCounter = total == 1 ? nil : "(\(completed)/\(total))"

        case .startingSamplesFetch:
            stagePrefix = "> starting raw samples…"
            stageLabel = nil
            stageCounter = nil

        case .readingSamples(let categoryID, let completed, let total):
            stagePrefix = "> samples · "
            stageLabel = friendlyName(for: categoryID)
            stageCounter = total == 1 ? nil : "(\(completed)/\(total))"

        case .serializing(_, let total):
            stagePrefix = total > 1 ? "> writing \(total) snapshots…" : "> writing snapshot…"
            stageLabel = nil
            stageCounter = nil

        case .delivering(let sinkID, let day, let total):
            stagePrefix = total > 1
                ? "> \(sinkID): pushing day \(day + 1)/\(total)"
                : "> \(sinkID): pushing…"
            stageLabel = nil
            stageCounter = nil

        case .retrying(let sinkID, let attempt, let totalAttempts, let reason):
            stagePrefix = "> \(sinkID): retry \(attempt)/\(totalAttempts) · \(reason)"
            stageLabel = nil
            stageCounter = nil

        case .finished:
            stagePrefix = ""
            stageLabel = nil
            stageCounter = nil
        }
    }
}
