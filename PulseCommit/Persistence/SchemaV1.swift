import Foundation
import SwiftData

typealias HistoryEntryStatus = HistoryEntry.Status

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    static var models: [any PersistentModel.Type] {
        [HistoryEntry.self, ExportCursor.self]
    }

    @Model
    final class HistoryEntry {
        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var finishedAt: Date
        var statusRaw: String
        var sinksJoined: String
        var daysCoveredJoined: String
        var errorMessage: String?
        var errorKind: String?
        var githubCommitSha: String?
        var githubCommitURLString: String?
        var githubBranch: String?
        var telegramMessageReference: String?

        init(
            id: UUID = UUID(),
            startedAt: Date,
            finishedAt: Date,
            status: HistoryEntryStatus,
            sinks: [String],
            daysCovered: [String],
            errorMessage: String? = nil,
            errorKind: String? = nil,
            githubCommitSha: String? = nil,
            githubCommitURLString: String? = nil,
            githubBranch: String? = nil,
            telegramMessageReference: String? = nil
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
        }
    }

    @Model
    final class ExportCursor {
        @Attribute(.unique) var key: String
        var lastSuccessfulExportAt: Date?

        init(key: String = "main", lastSuccessfulExportAt: Date? = nil) {
            self.key = key
            self.lastSuccessfulExportAt = lastSuccessfulExportAt
        }
    }
}
