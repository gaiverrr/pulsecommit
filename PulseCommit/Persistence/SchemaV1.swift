import Foundation
import SwiftData

/// Versioned schema container for Pulse Commit's SwiftData store.
///
/// Wrapping the persistent models in a `VersionedSchema` lets future field
/// additions or removals ship as explicit `MigrationStage`s rather than
/// hitting SwiftData's destructive-rewrite fallback (which silently drops
/// user history). All `ModelContainer` constructions in the app go through
/// `Schema(versionedSchema: SchemaV1.self)` + `PulseCommitMigrationPlan`.
///
/// **Schema history**
///
/// - `1.0.0` — initial release. `HistoryEntry` had no `errorKind` field.
/// - `1.1.0` — added `HistoryEntry.errorKind: String?` (the only optional
///   field added since launch). SwiftData lightweight migration handled the
///   bump in production without a stage because the new column is optional
///   and defaults to `nil` for pre-1.1 rows; no `MigrationStage` is required.
///   This file backfills schema versioning *after* the field was added, so
///   `SchemaV1` represents the live shape including `errorKind`.
///
/// Future field additions should also be additive + optional where possible.
/// Once a destructive change is needed, introduce `SchemaV2`, list both
/// versions in `PulseCommitMigrationPlan.schemas`, and provide a
/// `MigrationStage.custom(...)` (or `.lightweight(...)` if compatible).
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 1, 0) }

    static var models: [any PersistentModel.Type] {
        [HistoryEntry.self, ExportCursor.self]
    }
}

/// Migration plan for the Pulse Commit persistent store. Currently registers
/// only `SchemaV1` — there are no cross-version migrations yet, but the plan
/// is wired so future schema bumps can append stages without changing
/// `ModelContainer` call sites.
enum PulseCommitMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] { [] }
}
