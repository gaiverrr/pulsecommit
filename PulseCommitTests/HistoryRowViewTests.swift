import XCTest
@testable import PulseCommit

@MainActor
final class HistoryRowViewTests: XCTestCase {
    private func makeRow(outcome: HistoryRowModel.Outcome, id: UUID = UUID()) -> HistoryRowModel {
        HistoryRowModel(
            id: id,
            outcome: outcome,
            shortHash: "abc12345",
            dateLabel: "2026-05-10",
            relativeTime: "Today · 14:30",
            summary: "—",
            sinkBadges: []
        )
    }

    func test_rowsAreTappable_whenEntryProviderReturnsEntry() {
        let id = UUID()
        let row = makeRow(outcome: .failed, id: id)
        let snapshot = HistoryEntrySnapshot(
            id: id,
            startedAt: Date(),
            finishedAt: Date(),
            status: .failed,
            sinks: [],
            daysCovered: [],
            errorMessage: "Telegram 400"
        )
        let view = HistoryView(
            rows: [row],
            totalCommits: 1,
            totalFailures: 1,
            sinceLabel: "May 2026",
            entryProvider: { lookupId in lookupId == id ? snapshot : nil }
        )
        XCTAssertTrue(view.rowIsTappable(row))
    }

    func test_rowsNotTappable_withoutEntryProvider() {
        let row = makeRow(outcome: .failed)
        let view = HistoryView(
            rows: [row],
            totalCommits: 1,
            totalFailures: 1,
            sinceLabel: "May 2026"
        )
        XCTAssertFalse(view.rowIsTappable(row))
    }
}
