import Foundation
import SwiftData

@MainActor
final class HistoryStore {
    /// `nil` container = no-op mode. Used as a launch-time degradation when
    /// both `onDisk()` and `inMemory()` fail to construct a `ModelContainer`
    /// (e.g., schema migration conflict after an app update). Writes are
    /// silently discarded, reads return empty results, and the app continues
    /// to launch instead of crashing. The fault is logged at construction.
    private let container: ModelContainer?

    init(container: ModelContainer) {
        self.container = container
    }

    private init(noOp: Void) {
        self.container = nil
    }

    static func inMemory() throws -> HistoryStore {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PulseCommitMigrationPlan.self,
            configurations: config
        )
        return HistoryStore(container: container)
    }

    static func onDisk() throws -> HistoryStore {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: PulseCommitMigrationPlan.self
        )
        return HistoryStore(container: container)
    }

    /// Last-resort degradation when no `ModelContainer` can be constructed.
    /// Methods become no-ops; the app keeps launching. Callers must log the
    /// originating error before substituting this instance.
    static func noOp() -> HistoryStore {
        HistoryStore(noOp: ())
    }

    var isNoOp: Bool { container == nil }

    func append(_ entry: HistoryEntry) throws {
        guard let container else { return }
        let context = ModelContext(container)
        context.insert(entry)
        try context.save()
    }

    func appendAndAdvanceCursor(_ entry: HistoryEntry, cursor newCursor: Date) throws {
        guard let container else { return }
        let context = ModelContext(container)
        context.insert(entry)
        let descriptor = FetchDescriptor<ExportCursor>(
            predicate: #Predicate { $0.key == "main" }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.lastSuccessfulExportAt = newCursor
        } else {
            context.insert(ExportCursor(key: "main", lastSuccessfulExportAt: newCursor))
        }
        try context.save()
    }

    /// Returns value snapshots — SwiftData `@Model` instances must not
    /// outlive the `ModelContext` that fetched them. Callers (notably SwiftUI
    /// `@State` and navigation destinations) hold these across view lifetime.
    func recentEntries(limit: Int) throws -> [HistoryEntrySnapshot] {
        guard let container else { return [] }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).map(HistoryEntrySnapshot.init(entry:))
    }

    func latestGitHubCommitEntry() throws -> HistoryEntrySnapshot? {
        guard let container else { return nil }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { $0.githubCommitSha != nil },
            sortBy: [SortDescriptor(\.finishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.map(HistoryEntrySnapshot.init(entry:))
    }

    /// Returns the persisted cursor date as a value snapshot. The underlying
    /// `ExportCursor` entity is fetched in a short-lived `ModelContext` and
    /// the value is copied out before the context is deallocated — model
    /// objects must never outlive their context (SwiftData undefined behavior).
    /// Lazily inserts a default `ExportCursor(key: "main", date: nil)` if none
    /// exists so subsequent `setCursor(...)` calls update rather than insert.
    func cursor() throws -> Date? {
        guard let container else { return nil }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ExportCursor>(
            predicate: #Predicate { $0.key == "main" }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing.lastSuccessfulExportAt
        }
        context.insert(ExportCursor(key: "main", lastSuccessfulExportAt: nil))
        try context.save()
        return nil
    }

    func deleteAll() throws {
        guard let container else { return }
        let context = ModelContext(container)
        try context.delete(model: HistoryEntry.self)
        try context.delete(model: ExportCursor.self)
        try context.save()
    }

    func setCursor(_ date: Date?) throws {
        guard let container else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ExportCursor>(
            predicate: #Predicate { $0.key == "main" }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.lastSuccessfulExportAt = date
        } else {
            context.insert(ExportCursor(key: "main", lastSuccessfulExportAt: date))
        }
        try context.save()
    }
}
