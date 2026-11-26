import Foundation
import SwiftData

/// Stable identifiers for `HistoryEntry.errorKind`. String constants (not an
/// enum) so the persisted value tolerates unknown future kinds — readers
/// match on the canonical strings and ignore anything else.
enum HistoryErrorKind {
    static let sessionExpired = "sessionExpired"
    static let consentRequired = "consentRequired"
    /// The run could not read HealthKit because the device was locked and the
    /// Health database was protected (Data Protection). Distinct from a real
    /// failure: nothing was delivered and the cursor was left untouched so the
    /// day is re-exported on the next unlocked run.
    static let deviceLocked = "deviceLocked"
    /// Every enabled category failed to read for the whole window (each one
    /// threw, recorded in `unavailableCategories`). Positive evidence of an
    /// error — a transient HealthKit failure, or possibly denied access.
    /// Nothing was delivered and the cursor was left untouched.
    static let healthDataUnreadable = "healthDataUnreadable"
    /// iOS positively reported that an enabled category lacks enough readable
    /// history for the requested range or one of its required query lookbacks.
    static let limitedHealthHistory = "limitedHealthHistory"
    /// iOS 27 could not complete the limited-history preflight. The run fails
    /// closed without persisting any native type names or boundary dates.
    static let healthHistoryCheckFailed = "healthHistoryCheckFailed"
    /// The requested range resolved to zero completed days (e.g. a range
    /// entirely inside today). Nothing to export; not a failure of the app.
    static let emptyRange = "emptyRange"
}

@Model
final class HistoryEntry {
    enum Status: String, Codable, Sendable {
        case success
        case failed
        case paywalled
    }

    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var finishedAt: Date
    var statusRaw: String
    var sinksJoined: String
    var daysCoveredJoined: String
    var errorMessage: String?
    /// Structured kind tag for the failure recorded in `errorMessage`.
    /// Used by UI layers to make typed decisions (e.g. session-expiry banner)
    /// without substring-matching on the human-readable error text. Persisted
    /// as `String?` so SwiftData lightweight migration handles the schema bump
    /// without a `VersionedSchema`.
    ///
    /// Known values: `"sessionExpired"`. New kinds can be added additively.
    var errorKind: String?
    var githubCommitSha: String?
    var githubCommitURLString: String?
    var githubBranch: String?
    var telegramMessageReference: String?
    var webhookReference: String?

    init(
        id: UUID = UUID(),
        startedAt: Date,
        finishedAt: Date,
        status: Status,
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
        self.statusRaw = status.rawValue
        self.sinksJoined = sinks.joined(separator: ",")
        self.daysCoveredJoined = daysCovered.joined(separator: ",")
        self.errorMessage = errorMessage
        self.errorKind = errorKind
        self.githubCommitSha = githubCommitSha
        self.githubCommitURLString = githubCommitURLString
        self.githubBranch = githubBranch
        self.telegramMessageReference = telegramMessageReference
        self.webhookReference = webhookReference
    }

    // MARK: Derived accessors
    //
    // The three properties below are computed from stored columns.
    // **Never reference them from a `#Predicate` closure** — SwiftData's
    // predicate macro cannot translate non-stored properties and crashes
    // at runtime with an opaque key-path failure. Filter on the underlying
    // stored fields instead:
    //   - `status`        → predicate on `statusRaw`
    //   - `sinks`         → predicate on `sinksJoined`
    //   - `daysCovered`   → predicate on `daysCoveredJoined`
    // `@Transient` is the strongest signal we can give the macro that
    // these are not persisted and not predicate-safe.

    @Transient
    var status: Status {
        Status(rawValue: statusRaw) ?? .failed
    }

    @Transient
    var sinks: [String] {
        sinksJoined.isEmpty ? [] : sinksJoined.split(separator: ",").map(String.init)
    }

    @Transient
    var daysCovered: [String] {
        daysCoveredJoined.isEmpty ? [] : daysCoveredJoined.split(separator: ",").map(String.init)
    }
}
