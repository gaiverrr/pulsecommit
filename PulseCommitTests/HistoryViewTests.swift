import XCTest
@testable import PulseCommit

@MainActor
final class HistoryViewTests: XCTestCase {
    private func makeRow(id: UUID = UUID(), outcome: HistoryRowModel.Outcome) -> HistoryRowModel {
        HistoryRowModel(
            id: id,
            outcome: outcome,
            shortHash: "abc12345",
            dateLabel: "2026-05-10",
            relativeTime: "Today · 14:30",
            summary: outcome == .success ? "exported 1 day" : "github 401",
            sinkBadges: [.init(label: "github", ok: outcome == .success)]
        )
    }

    func test_filterAll_includesEverything() {
        let view = HistoryView(
            rows: [makeRow(outcome: .success), makeRow(outcome: .failed)],
            totalCommits: 2,
            totalFailures: 1,
            sinceLabel: "May 2026"
        )
        XCTAssertEqual(view.filteredRows.count, 2)
    }

    func test_filterMatchesSuccessOnly() {
        let success = makeRow(outcome: .success)
        let failed = makeRow(outcome: .failed)
        let filter = HistoryFilter.success
        XCTAssertTrue(filter.matches(success))
        XCTAssertFalse(filter.matches(failed))
    }

    func test_filterMatchesFailedOnly() {
        let success = makeRow(outcome: .success)
        let failed = makeRow(outcome: .failed)
        let filter = HistoryFilter.failed
        XCTAssertFalse(filter.matches(success))
        XCTAssertTrue(filter.matches(failed))
    }

    func test_modelFromSuccessEntry_setsSummaryAndBadges() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = HistoryEntry(
            startedAt: started,
            finishedAt: started.addingTimeInterval(60),
            status: .success,
            sinks: ["github", "telegram"],
            daysCovered: ["2026-04-09", "2026-04-10"],
            githubCommitSha: "a8f3c2dabcdef0123456789"
        )
        let row = HistoryRowModel.from(entry: entry, now: started.addingTimeInterval(60))
        XCTAssertEqual(row.outcome, .success)
        XCTAssertEqual(row.shortHash, "a8f3c2da")
        XCTAssertEqual(row.summary, "exported 2 days")
        XCTAssertEqual(row.sinkBadges.count, 2)
        XCTAssertTrue(row.sinkBadges.allSatisfy { $0.ok })
    }

    func test_modelFromFailedEntry_usesErrorMessageAndRedBadges() {
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = HistoryEntry(
            startedAt: started,
            finishedAt: started.addingTimeInterval(60),
            status: .failed,
            sinks: ["github"],
            daysCovered: ["2026-04-09"],
            errorMessage: "GitHub 401 · cursor not advanced"
        )
        let row = HistoryRowModel.from(entry: entry)
        XCTAssertEqual(row.outcome, .failed)
        XCTAssertEqual(row.summary, "GitHub 401 · cursor not advanced")
        XCTAssertFalse(row.sinkBadges[0].ok)
    }

    func test_relativeTime_useToday_whenSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let entry = HistoryEntry(
            startedAt: started,
            finishedAt: started,
            status: .success,
            sinks: [],
            daysCovered: []
        )
        let row = HistoryRowModel.from(entry: entry, now: started, calendar: calendar)
        XCTAssertTrue(row.relativeTime.hasPrefix("Today · "))
    }
}
