import XCTest
@testable import PulseCommit

@MainActor
final class HistoryStoreTests: XCTestCase {
    func test_append_and_recentEntries_reverseChronological() throws {
        let store = try HistoryStore.inMemory()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let older = HistoryEntry(
            startedAt: now.addingTimeInterval(-3600),
            finishedAt: now.addingTimeInterval(-3500),
            status: .success,
            sinks: ["github"],
            daysCovered: ["2026-04-09"]
        )
        let newer = HistoryEntry(
            startedAt: now,
            finishedAt: now.addingTimeInterval(60),
            status: .failed,
            sinks: ["github", "telegram"],
            daysCovered: ["2026-04-09", "2026-04-10"],
            errorMessage: "boom"
        )

        try store.append(older)
        try store.append(newer)

        let snapshots = try store.recentEntries(limit: 10)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].startedAt, newer.startedAt)
        XCTAssertEqual(snapshots[0].status, .failed)
        XCTAssertEqual(snapshots[0].sinks, ["github", "telegram"])
        XCTAssertEqual(snapshots[0].errorMessage, "boom")
        XCTAssertEqual(snapshots[1].startedAt, older.startedAt)
        XCTAssertEqual(snapshots[1].status, .success)
    }

    func test_legacyPaywalledRowStillLoadsAndRendersAsFailure() throws {
        let store = try HistoryStore.inMemory()
        let entry = HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_001),
            status: .failed,
            sinks: ["github"],
            daysCovered: [],
            errorMessage: "trial exhausted"
        )
        entry.statusRaw = "paywalled"
        try store.append(entry)

        let snapshots = try store.recentEntries(limit: 10)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots[0].status, .paywalled)
        XCTAssertEqual(snapshots[0].errorMessage, "trial exhausted")
        XCTAssertEqual(HistoryRowModel.from(snapshot: snapshots[0]).outcome, .failed)
        XCTAssertEqual(HistoryRowModel.from(snapshot: snapshots[0]).summary, "Export blocked by a limit removed in 1.0")
        XCTAssertEqual(HistoryDetailView(entry: snapshots[0]).fullErrorMessage, "Export blocked by a limit removed in 1.0")
        XCTAssertEqual(try store.recentEntries(limit: 10)[0].errorMessage, "trial exhausted")
    }

    func test_displayErrorMessage_neutralizesLegacyPaidTierMessages() {
        let neutral = "Export blocked by a limit removed in 1.0"
        XCTAssertEqual(HistoryEntrySnapshot.displayErrorMessage(status: .paywalled, errorMessage: "range requires unlock"), neutral)
        XCTAssertEqual(HistoryEntrySnapshot.displayErrorMessage(status: .paywalled, errorMessage: nil), neutral)
        XCTAssertEqual(HistoryEntrySnapshot.displayErrorMessage(status: .failed, errorMessage: "trial exhausted"), neutral)
        XCTAssertEqual(HistoryEntrySnapshot.displayErrorMessage(status: .failed, errorMessage: "lastNDays requires unlock"), neutral)
        XCTAssertEqual(HistoryEntrySnapshot.displayErrorMessage(status: .failed, errorMessage: "sink failed: timeout"), "sink failed: timeout")
        XCTAssertNil(HistoryEntrySnapshot.displayErrorMessage(status: .failed, errorMessage: nil))
    }

    func test_recentEntries_returnsValueSnapshotsNotLiveEntities() throws {
        let store = try HistoryStore.inMemory()
        try store.append(HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_060),
            status: .success,
            sinks: ["github"],
            daysCovered: ["2026-04-09"],
            githubCommitSha: "deadbeef0011",
            githubCommitURLString: "https://github.com/owner/repo/commit/deadbeef0011",
            githubBranch: "main",
            telegramMessageReference: "12345"
        ))
        let snapshots: [HistoryEntrySnapshot] = try store.recentEntries(limit: 10)
        XCTAssertEqual(snapshots.count, 1)
        let snap = snapshots[0]
        XCTAssertEqual(snap.githubCommitSha, "deadbeef0011")
        XCTAssertEqual(snap.githubCommitURLString, "https://github.com/owner/repo/commit/deadbeef0011")
        XCTAssertEqual(snap.githubBranch, "main")
        XCTAssertEqual(snap.telegramMessageReference, "12345")
        XCTAssertEqual(snap.sinks, ["github"])
        XCTAssertEqual(snap.daysCovered, ["2026-04-09"])
    }

    func test_recentEntries_limit() throws {
        let store = try HistoryStore.inMemory()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<5 {
            try store.append(HistoryEntry(
                startedAt: base.addingTimeInterval(TimeInterval(i * 60)),
                finishedAt: base.addingTimeInterval(TimeInterval(i * 60 + 10)),
                status: .success,
                sinks: ["github"],
                daysCovered: ["2026-04-09"]
            ))
        }
        let entries = try store.recentEntries(limit: 3)
        XCTAssertEqual(entries.count, 3)
    }

    func test_cursor_returnsNilWhenNeverPersisted() throws {
        let store = try HistoryStore.inMemory()
        let cursorDate = try store.cursor()
        XCTAssertNil(cursorDate)
    }

    func test_cursor_returnsDateValueNotEntity() throws {
        let store = try HistoryStore.inMemory()
        let date = Date(timeIntervalSince1970: 1_700_111_222)
        try store.setCursor(date)
        let cursorDate: Date? = try store.cursor()
        XCTAssertEqual(cursorDate, date)
    }

    func test_setCursor_updatesAndPersists() throws {
        let store = try HistoryStore.inMemory()
        _ = try store.cursor()
        let date = Date(timeIntervalSince1970: 1_700_001_234)
        try store.setCursor(date)
        XCTAssertEqual(try store.cursor(), date)
    }

    func test_setCursor_createsIfMissing() throws {
        let store = try HistoryStore.inMemory()
        let date = Date(timeIntervalSince1970: 1_700_005_678)
        try store.setCursor(date)
        XCTAssertEqual(try store.cursor(), date)
    }
}
