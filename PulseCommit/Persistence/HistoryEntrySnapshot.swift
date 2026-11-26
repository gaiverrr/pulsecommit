import Foundation

/// Value snapshot of a `HistoryEntry` that can safely cross view boundaries.
/// SwiftData `@Model` instances must not outlive their `ModelContext`; passing
/// them into `@State` or navigation destinations is undefined behavior. The
/// UI layer reads this struct instead — `HistoryStore.recentEntries(limit:)`
/// copies fields out inside the same short-lived context that fetched them.
struct HistoryEntrySnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let status: HistoryEntry.Status
    let sinks: [String]
    let daysCovered: [String]
    let errorMessage: String?
    let errorKind: String?
    let githubCommitSha: String?
    let githubCommitURLString: String?
    let githubBranch: String?
    let telegramMessageReference: String?
    let webhookReference: String?

    init(
        id: UUID,
        startedAt: Date,
        finishedAt: Date,
        status: HistoryEntry.Status,
        sinks: [String],
        daysCovered: [String],
        errorMessage: String? = nil,
        errorKind: String? = nil,
        githubCommitSha: String? = nil,
        githubCommitURLString: String? = nil,
        githubBranch: String? = nil,
        telegramMessageReference: String? = nil,
        webhookReference: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.sinks = sinks
        self.daysCovered = daysCovered
        self.errorMessage = errorMessage
        self.errorKind = errorKind
        self.githubCommitSha = githubCommitSha
        self.githubCommitURLString = githubCommitURLString
        self.githubBranch = githubBranch
        self.telegramMessageReference = telegramMessageReference
        self.webhookReference = webhookReference
    }

    static let removedLimitMessage = "Export blocked by a limit removed in 1.0"

    var displayErrorMessage: String? {
        Self.displayErrorMessage(status: status, errorMessage: errorMessage)
    }

    static func displayErrorMessage(status: HistoryEntry.Status, errorMessage: String?) -> String? {
        if status == .paywalled { return removedLimitMessage }
        guard let errorMessage else { return nil }
        if errorMessage == "trial exhausted" || errorMessage.hasSuffix("requires unlock") {
            return removedLimitMessage
        }
        return errorMessage
    }

    init(entry: HistoryEntry) {
        self.init(
            id: entry.id,
            startedAt: entry.startedAt,
            finishedAt: entry.finishedAt,
            status: entry.status,
            sinks: entry.sinks,
            daysCovered: entry.daysCovered,
            errorMessage: entry.errorMessage,
            errorKind: entry.errorKind,
            githubCommitSha: entry.githubCommitSha,
            githubCommitURLString: entry.githubCommitURLString,
            githubBranch: entry.githubBranch,
            telegramMessageReference: entry.telegramMessageReference,
            webhookReference: entry.webhookReference
        )
    }
}
