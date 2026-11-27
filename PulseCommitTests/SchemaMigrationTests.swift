import CoreData
import XCTest
import SwiftData
@testable import PulseCommit

@MainActor
final class SchemaMigrationTests: XCTestCase {
    func test_schemaV1_versionIsRegistered() {
        XCTAssertEqual(SchemaV1.versionIdentifier, Schema.Version(1, 1, 0))
        let modelNames = SchemaV1.models.map { String(describing: $0) }.sorted()
        XCTAssertEqual(modelNames, ["ExportCursor", "HistoryEntry"])
    }

    func test_migrationPlan_registersBothSchemasWithOneStage() {
        let schemaNames = PulseCommitMigrationPlan.schemas
            .map { String(describing: $0) }
        XCTAssertEqual(schemaNames, ["SchemaV1", "SchemaV2"])
        XCTAssertEqual(PulseCommitMigrationPlan.stages.count, 1)
        XCTAssertEqual(SchemaV2.versionIdentifier, Schema.Version(1, 2, 0))
        XCTAssertEqual(SchemaV2.models.map { String(describing: $0) }.sorted(), ["ExportCursor", "HistoryEntry"])
    }

    private let shippedVersionHashes = [
        "ExportCursor": "AzCQz6Ej+MHx15NkR0sn4XqR6VoH6sMovzS9sOY1Zco=",
        "HistoryEntry": "Fc5Vn7W+HiYfEjQYBad44WwD4j95wCZ5XXjLBVDwGAM="
    ]

    private func makeStoreURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("schema-upgrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("history.store")
    }

    private func writeSchemaV1Store(at url: URL) throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        context.insert(SchemaV1.HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_764_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_764_000_060),
            status: .success,
            sinks: ["github", "telegram"],
            daysCovered: ["2026-11-24"],
            githubCommitSha: "abc1234",
            telegramMessageReference: "chat 42"
        ))
        context.insert(SchemaV1.HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_764_100_000),
            finishedAt: Date(timeIntervalSince1970: 1_764_100_030),
            status: .failed,
            sinks: ["telegram"],
            daysCovered: ["2026-11-25"],
            errorMessage: "boom",
            errorKind: HistoryErrorKind.sessionExpired
        ))
        context.insert(SchemaV1.ExportCursor(key: "main", lastSuccessfulExportAt: Date(timeIntervalSince1970: 1_764_000_000)))
        try context.save()
    }

    func test_schemaV1Store_matchesShippedModelVersionHashes() throws {
        let url = try makeStoreURL()
        try writeSchemaV1Store(at: url)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let hashes = try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        XCTAssertEqual(hashes.mapValues { $0.base64EncodedString() }, shippedVersionHashes)
    }

    func test_schemaV1Store_upgradesThroughProductionPlanAndKeepsRows() throws {
        let url = try makeStoreURL()
        try writeSchemaV1Store(at: url)

        let store = try HistoryStore.onDisk(url: url)
        let rows = try store.recentEntries(limit: 10)
        XCTAssertEqual(rows.count, 2)
        let failed = try XCTUnwrap(rows.first)
        XCTAssertEqual(failed.status, .failed)
        XCTAssertEqual(failed.errorMessage, "boom")
        XCTAssertEqual(failed.errorKind, HistoryErrorKind.sessionExpired)
        XCTAssertNil(failed.webhookReference)
        let success = try XCTUnwrap(rows.last)
        XCTAssertEqual(success.status, .success)
        XCTAssertEqual(success.sinks, ["github", "telegram"])
        XCTAssertEqual(success.githubCommitSha, "abc1234")
        XCTAssertEqual(success.telegramMessageReference, "chat 42")
        XCTAssertEqual(try store.cursor(), Date(timeIntervalSince1970: 1_764_000_000))

        try store.append(HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_764_200_000),
            finishedAt: Date(timeIntervalSince1970: 1_764_200_010),
            status: .success,
            sinks: ["webhook"],
            daysCovered: ["2026-11-26"],
            webhookReference: "hooks.example.com HTTP 200"
        ))
        XCTAssertEqual(try store.recentEntries(limit: 1).first?.webhookReference, "hooks.example.com HTTP 200")
        XCTAssertEqual(try store.recentEntries(limit: 10).count, 3)
    }

    func test_inMemoryStore_opensWithVersionedSchemaAndMigrationPlan() throws {
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
