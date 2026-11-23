import XCTest
@testable import PulseCommit

final class ExportWindowResolverTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let day: TimeInterval = 24 * 60 * 60

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func testLastDayOnlyIsYesterdayOnly() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:34:56Z")
        let result = resolver.resolve(mode: .lastDayOnly, cursor: nil, now: now)
        XCTAssertEqual(
            result,
            .proceed(from: iso("2026-04-09T00:00:00Z"), to: iso("2026-04-10T00:00:00Z"))
        )
    }

    func testIncrementalUsesCursorAsFromAndTodayAsTo() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let cursor = iso("2026-04-03T00:00:00Z")
        let result = resolver.resolve(mode: .incremental, cursor: cursor, now: now)
        XCTAssertEqual(result, .proceed(from: cursor, to: iso("2026-04-10T00:00:00Z")))
    }

    func testIncrementalWithoutCursorFallsBackToYesterday() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let result = resolver.resolve(mode: .incremental, cursor: nil, now: now)
        XCTAssertEqual(
            result,
            .proceed(from: iso("2026-04-09T00:00:00Z"), to: iso("2026-04-10T00:00:00Z"))
        )
    }

    func testIncrementalWithFutureCursorProducesEmptyWindow() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let futureCursor = iso("2026-04-15T00:00:00Z")
        let result = resolver.resolve(mode: .incremental, cursor: futureCursor, now: now)
        let today = iso("2026-04-10T00:00:00Z")
        XCTAssertEqual(result, .proceed(from: today, to: today))
    }

    func testLastNDaysCoversTheCompletedDaysBeforeToday() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let result = resolver.resolve(mode: .lastNDays(7), cursor: nil, now: now)
        XCTAssertEqual(
            result,
            .proceed(from: iso("2026-04-03T00:00:00Z"), to: iso("2026-04-10T00:00:00Z"))
        )
    }

    func testTodayLiveReturnsStartOfDayToNow() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T15:23:45Z")
        let result = resolver.resolve(mode: .todayLive, cursor: nil, now: now)
        XCTAssertEqual(result, .proceed(from: iso("2026-04-10T00:00:00Z"), to: now))
    }

    func testTodayLiveUsesLocalMidnightInLisbonJustBeforeAndAfterMidnight() {
        let timezone = TimeZone(identifier: "Europe/Lisbon")!
        let resolver = ExportWindowResolver(timezone: timezone)

        let beforeMidnight = iso("2026-09-19T22:59:59Z")
        XCTAssertEqual(
            resolver.resolve(mode: .todayLive, cursor: nil, now: beforeMidnight),
            .proceed(from: iso("2026-09-18T23:00:00Z"), to: beforeMidnight)
        )

        let afterMidnight = iso("2026-09-19T23:00:01Z")
        XCTAssertEqual(
            resolver.resolve(mode: .todayLive, cursor: nil, now: afterMidnight),
            .proceed(from: iso("2026-09-19T23:00:00Z"), to: afterMidnight)
        )
    }

    func testTodayLiveUsesCalendarStartAcrossSpringDSTTransition() {
        let timezone = TimeZone(identifier: "America/New_York")!
        let resolver = ExportWindowResolver(timezone: timezone)
        let now = iso("2026-03-08T07:30:00Z")

        XCTAssertEqual(
            resolver.resolve(mode: .todayLive, cursor: nil, now: now),
            .proceed(from: iso("2026-03-08T05:00:00Z"), to: now)
        )
    }

    func testRange_snapsMidDayEndpointsToDayBoundaries() {
        // Shortcuts date parameters carry a time of day ("Current Date - 3
        // days" is mid-day); committing partial days as full days is wrong.
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let from = now.addingTimeInterval(-3 * day)
        let result = resolver.resolve(mode: .range(from: from, to: now), cursor: nil, now: now)
        XCTAssertEqual(
            result,
            .proceed(from: iso("2026-04-07T00:00:00Z"), to: iso("2026-04-10T00:00:00Z"))
        )
    }

    func testRangeCoversTheFullLastDayWhenItIsAlreadyComplete() {
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let result = resolver.resolve(
            mode: .range(from: iso("2026-04-05T09:30:00Z"), to: iso("2026-04-07T18:45:00Z")),
            cursor: nil,
            now: now
        )
        XCTAssertEqual(
            result,
            .proceed(from: iso("2026-04-05T00:00:00Z"), to: iso("2026-04-08T00:00:00Z"))
        )
    }

    func testRangeIsInclusiveOfTheDayContainingTo() {
        // A range "from A to B" includes B's whole day. `to` at exactly
        // midnight belongs to that day (matching startOfDay semantics used
        // everywhere else), so 2026-04-08 00:00 includes 2026-04-08 → end
        // boundary 2026-04-09 00:00.
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let from = iso("2026-04-05T00:00:00Z")
        let to = iso("2026-04-08T00:00:00Z")
        let result = resolver.resolve(mode: .range(from: from, to: to), cursor: nil, now: now)
        XCTAssertEqual(result, .proceed(from: from, to: iso("2026-04-09T00:00:00Z")))
    }

    func testRangeEndIsContinuousAcrossTheMidnightBoundary() {
        // Regression: the previous exact-equality `to == startOfDay` test made
        // a sub-second difference flip a whole exported day. Midnight and just
        // after midnight must resolve to the same window.
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let from = iso("2026-04-05T00:00:00Z")
        let atMidnight = resolver.resolve(
            mode: .range(from: from, to: iso("2026-04-08T00:00:00Z")),
            cursor: nil, now: now
        )
        let justAfter = resolver.resolve(
            mode: .range(from: from, to: iso("2026-04-08T00:00:00Z").addingTimeInterval(0.4)),
            cursor: nil, now: now
        )
        XCTAssertEqual(atMidnight, justAfter)
    }

    func testRangeEntirelyWithinTodayResolvesToEmptyNotPhantomSuccess() {
        // from/to both inside the current (incomplete) day → no completed days
        // to export. Must be an explicit empty result, not proceed(from==to)
        // which downstream would record as a phantom success delivering nothing.
        let resolver = ExportWindowResolver(timezone: utc)
        let now = iso("2026-04-10T12:00:00Z")
        let result = resolver.resolve(
            mode: .range(from: iso("2026-04-10T06:00:00Z"), to: iso("2026-04-10T09:00:00Z")),
            cursor: nil,
            now: now
        )
        guard case .empty = result else {
            return XCTFail("expected .empty, got \(result)")
        }
    }
}
