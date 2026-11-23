import XCTest
@testable import PulseCommit

final class AutomaticWorkoutConsentAndPersistenceTests: XCTestCase {
    func test_receiptBindsExactTargetAndNonReversibleTokenFingerprint() throws {
        let a = AutomaticWorkoutConsentScope(chatID: "-1001", messageThreadID: 42, botToken: "secret-A")
        let changedToken = AutomaticWorkoutConsentScope(chatID: "-1001", messageThreadID: 42, botToken: "secret-B")
        let changedTopic = AutomaticWorkoutConsentScope(chatID: "-1001", messageThreadID: 43, botToken: "secret-A")

        XCTAssertNotEqual(a, changedToken)
        XCTAssertNotEqual(a, changedTopic)
        XCTAssertFalse(a.tokenFingerprint.contains("secret-A"))
        XCTAssertEqual(a.tokenFingerprint.count, 64)
    }

    func test_preferencesDefaultOffAndDestinationChangesInvalidateAutomaticReceipt() throws {
        let suite = "AutomaticWorkoutConsentAndPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let consent = AutomaticWorkoutConsentStore(defaults: defaults)
        let preferences = PreferencesStore(defaults: defaults)
        preferences.bindAutomaticWorkoutConsentStore(consent)
        let scope = AutomaticWorkoutConsentScope(chatID: "-1001", messageThreadID: nil, botToken: "token")

        XCTAssertFalse(preferences.automaticWorkoutTelegramEnabled)
        XCTAssertNotNil(consent.accept(scope))
        preferences.automaticWorkoutTelegramEnabled = true
        preferences.telegramThreadId = 9

        XCTAssertFalse(preferences.automaticWorkoutTelegramEnabled)
        XCTAssertNil(consent.record())
    }

    func test_fileStorePersistsMetadataAcrossInstancesAndFailsClosedOnCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomaticWorkoutAttemptStore-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("attempts.json")
        let id = UUID()
        let record = AutomaticWorkoutAttemptRecord(
            workoutID: id,
            workoutEndDate: Date(timeIntervalSince1970: 1_800_000_000),
            scopeID: "fingerprint-only-scope",
            attemptCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
            state: .deliveryUnknown
        )
        let first = AutomaticWorkoutAttemptFileStore(url: url)
        let saved = await first.save(record)
        XCTAssertTrue(saved)
        let second = AutomaticWorkoutAttemptFileStore(url: url)
        let reloaded = await second.lookup(id)
        XCTAssertEqual(reloaded, .found(record))

        try Data("not json".utf8).write(to: url, options: .atomic)
        let corrupt = AutomaticWorkoutAttemptFileStore(url: url)
        let corruptLookup = await corrupt.lookup(id)
        let corruptSave = await corrupt.save(record)
        XCTAssertEqual(corruptLookup, .unavailable)
        XCTAssertFalse(corruptSave)
    }

    func test_fileStoreLatestIsPartitionedByDestinationAndActivationScope() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomaticWorkoutAttemptStore-\(UUID().uuidString)", isDirectory: true)
        let store = AutomaticWorkoutAttemptFileStore(url: directory.appendingPathComponent("attempts.json"))
        let old = AutomaticWorkoutAttemptRecord(
            workoutID: UUID(),
            workoutEndDate: Date(timeIntervalSince1970: 1_800_000_000),
            scopeID: "chat-A:activation-1",
            attemptCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
            state: .deliveryUnknown
        )
        let current = AutomaticWorkoutAttemptRecord(
            workoutID: UUID(),
            workoutEndDate: Date(timeIntervalSince1970: 1_800_000_010),
            scopeID: "chat-B:activation-2",
            attemptCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_050),
            state: .delivered(messageID: 7)
        )
        let savedOld = await store.save(old)
        let savedCurrent = await store.save(current)
        XCTAssertTrue(savedOld)
        XCTAssertTrue(savedCurrent)

        let currentLatest = await store.latest(scopeID: current.scopeID)
        let freshActivation = await store.latest(scopeID: "chat-B:activation-3")
        XCTAssertEqual(currentLatest, .found(current))
        XCTAssertEqual(freshActivation, .missing)
        let oldLookup = await store.lookup(old.workoutID)
        XCTAssertEqual(oldLookup, .found(old))
    }

    func test_fileStoreFailsClosedWhenParseableEnvelopeContainsDuplicateWorkoutIDs() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutomaticWorkoutAttemptStore-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("attempts.json")
        let id = UUID()
        let record = AutomaticWorkoutAttemptRecord(
            workoutID: id,
            workoutEndDate: Date(timeIntervalSince1970: 1_800_000_000),
            scopeID: "scope",
            attemptCount: 1,
            updatedAt: Date(timeIntervalSince1970: 1_800_000_001),
            state: .sending
        )
        let writer = AutomaticWorkoutAttemptFileStore(url: url)
        let didWrite = await writer.save(record)
        XCTAssertTrue(didWrite)

        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        records.append(records[0])
        envelope["records"] = records
        try JSONSerialization.data(withJSONObject: envelope).write(to: url, options: .atomic)

        let reader = AutomaticWorkoutAttemptFileStore(url: url)
        let lookup = await reader.lookup(id)
        let didSave = await reader.save(record)
        XCTAssertEqual(lookup, .unavailable)
        XCTAssertFalse(didSave)
    }
}
