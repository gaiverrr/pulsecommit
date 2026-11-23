import AppIntents
import Foundation

enum WindowOption: String, AppEnum {
    case today
    case last1d
    case last7d
    case last30d

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Window")
    }

    static let caseDisplayRepresentations: [WindowOption: DisplayRepresentation] = [
        .today: "Today (in progress)",
        .last1d: "Last 1 day",
        .last7d: "Last 7 days",
        .last30d: "Last 30 days"
    ]
}

enum DestinationOption: String, AppEnum {
    case both
    case githubOnly
    case telegramOnly

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Destination")
    }

    static let caseDisplayRepresentations: [DestinationOption: DisplayRepresentation] = [
        .both: "Both",
        .githubOnly: "GitHub only",
        .telegramOnly: "Telegram only"
    ]

    var sinkIds: Set<String> {
        switch self {
        case .both: return ["github", "telegram"]
        case .githubOnly: return ["github"]
        case .telegramOnly: return ["telegram"]
        }
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noCategoriesEnabled
    case noDestinationsConfigured
    case invalidRange
    case consentRequired
    case limitedHealthHistory(String)
    case healthHistoryCheckFailed(String)
    case exportFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noCategoriesEnabled:
            return "No categories enabled. Open Pulse Commit and enable at least one category."
        case .noDestinationsConfigured:
            return "No destinations configured. Connect GitHub or Telegram in Pulse Commit."
        case .invalidRange:
            return "Invalid date range. 'From' must be earlier than 'To', within the last 365 days."
        case .consentRequired:
            return "Open Pulse Commit to review consent for this Health export destination."
        case .limitedHealthHistory(let reason), .healthHistoryCheckFailed(let reason):
            return "\(reason)"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

@MainActor
enum IntentRunner {
    static func exportMode(for window: WindowOption) -> ExportRequest.Mode {
        switch window {
        case .today:
            return .todayLive
        case .last1d:
            return .lastDayOnly
        case .last7d:
            return .lastNDays(7)
        case .last30d:
            return .lastNDays(30)
        }
    }

    static func configuredSinkIds(_ container: AppContainer) async -> Set<String> {
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
    }

    static func request(
        mode: ExportRequest.Mode,
        sinkFilter: Set<String>? = nil,
        container: AppContainer
    ) async throws -> ExportRequest {
        let configured = await configuredSinkIds(container)
        let sinks: Set<String>
        if let sinkFilter {
            sinks = configured.intersection(sinkFilter)
        } else {
            sinks = configured
        }
        if sinks.isEmpty {
            throw IntentError.noDestinationsConfigured
        }
        let categories = container.preferences.enabledCategoryIds
        if categories.isEmpty {
            throw IntentError.noCategoriesEnabled
        }
        return ExportRequest(
            mode: mode,
            enabledCategoryIds: categories,
            enabledSinkIds: sinks
        )
    }

    static func run(
        mode: ExportRequest.Mode,
        sinkFilter: Set<String>? = nil,
        container: AppContainer? = nil
    ) async throws -> String {
        let container = container ?? AppContainer.shared
        let request = try await request(
            mode: mode,
            sinkFilter: sinkFilter,
            container: container
        )
        let orchestrator = await container.orchestratorFactory()
        if await !orchestrator.hasCurrentConsent(for: request) {
            throw IntentError.consentRequired
        }
        let result = await orchestrator.runResult(request)
        switch result.status {
        case .success:
            return "ok"
        case .failed, .paywalled:
            if let coverageError = result.coverageError {
                switch coverageError {
                case .limitedHistory:
                    throw IntentError.limitedHealthHistory(coverageError.userMessage)
                case .checkFailed:
                    throw IntentError.healthHistoryCheckFailed(coverageError.userMessage)
                }
            }
            let latest = (try? container.history.recentEntries(limit: 1))?.first
            if latest?.errorKind == HistoryErrorKind.consentRequired {
                throw IntentError.consentRequired
            }
            throw IntentError.exportFailed("see history")
        }
    }
}
