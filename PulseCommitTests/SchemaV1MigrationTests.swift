import XCTest
import SwiftData
@testable import PulseCommit

/// Sanity checks for the versioned schema scaffolding. We cannot easily
/// synthesize a pre-1.0 on-disk store from inside the test target (SwiftData
/// stores live in the host app's Application Support directory and SchemaV1
/// represents the live shape), so these tests assert the wiring is correct
/// and the store opens cleanly with the migration plan attached.
@MainActor
final class SchemaV1MigrationTests: XCTestCase {
    func test_schemaV1_versionIsRegistered() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 1, 0))
        let modelNames = SchemaV1.models.map { String(describing: $0) }.sorted()
        XCTAssertEqual(modelNames, ["ExportCursor", "HistoryEntry"])
    }

    func test_migrationPlan_registersSchemaV1() {
        let schemaNames = PulseCommitMigrationPlan.schemas
            .map { String(describing: $0) }
        XCTAssertEqual(schemaNames, ["SchemaV1"])
        XCTAssertTrue(PulseCommitMigrationPlan.stages.isEmpty)
    }

    func test_inMemoryStore_opensWithVersionedSchemaAndMigrationPlan() throws {
        // Round-trips the migration plan + Schema(versionedSchema:) wiring
        // through ModelContainer — verifies SchemaV1 is well-formed.
        let store = try HistoryStore.inMemory()
        XCTAssertFalse(store.isNoOp)
        let entry = HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_060),
            status: .success,
            sinks: ["github"],
            daysCovered: ["2026-04-09"]
        )
        try store.append(entry)
        XCTAssertEqual(try store.recentEntries(limit: 5).count, 1)
    }

    /// errorKind was added post-launch via SwiftData lightweight migration
    /// (pre-1.1 rows default to nil). SchemaV1 documents this as the live
    /// 1.1 shape, so new inserts can omit it without round-trip loss.
    func test_historyEntry_errorKindDefaultsToNil() throws {
        let store = try HistoryStore.inMemory()
        try store.append(HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_060),
            status: .failed,
            sinks: ["github"],
            daysCovered: ["2026-04-09"],
            errorMessage: "boom"
        ))
        let snap = try XCTUnwrap(try store.recentEntries(limit: 1).first)
        XCTAssertNil(snap.errorKind)
    }
}
