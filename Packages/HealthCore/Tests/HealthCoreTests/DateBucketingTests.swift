import XCTest
@testable import HealthCore

final class DateBucketingTests: XCTestCase {
    private let nyc = TimeZone(identifier: "America/New_York")!
    private let utc = TimeZone(identifier: "UTC")!

    private func iso(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)!
    }

    func test_dayKey_inUTC() {
        XCTAssertEqual(DateBucketing.dayKey(iso("2024-06-15T13:45:00Z"), in: utc), "2024-06-15")
    }

    func test_dayKey_inLocalTimezoneCrossesUTCMidnight() {
        // 2024-06-15T02:00:00Z is 2024-06-14T22:00:00-04:00 in NYC.
        XCTAssertEqual(DateBucketing.dayKey(iso("2024-06-15T02:00:00Z"), in: nyc), "2024-06-14")
    }

    func test_dayKey_acrossDSTForwardBoundary() {
        // DST forward in NYC: 2024-03-10 02:00 → 03:00 local.
        // 2024-03-10T07:30:00Z = 03:30 EDT after spring-forward → still 2024-03-10.
        XCTAssertEqual(DateBucketing.dayKey(iso("2024-03-10T07:30:00Z"), in: nyc), "2024-03-10")
        // Just before forward, 2024-03-10T06:30:00Z = 01:30 EST → 2024-03-10.
        XCTAssertEqual(DateBucketing.dayKey(iso("2024-03-10T06:30:00Z"), in: nyc), "2024-03-10")
    }

    func test_daysCovered_returnsContiguousKeysInclusive() {
        let from = iso("2024-06-15T10:00:00Z")
        let to = iso("2024-06-17T10:00:00Z")
        XCTAssertEqual(
            DateBucketing.daysCovered(from: from, to: to, in: utc),
            ["2024-06-15", "2024-06-16", "2024-06-17"]
        )
    }

    func test_daysCovered_singleDayWhenSameDay() {
        let from = iso("2024-06-15T01:00:00Z")
        let to = iso("2024-06-15T23:00:00Z")
        XCTAssertEqual(DateBucketing.daysCovered(from: from, to: to, in: utc), ["2024-06-15"])
    }

    func test_daysCovered_acrossDSTForwardIsStillContiguous() {
        let from = iso("2024-03-09T12:00:00Z")
        let to = iso("2024-03-11T12:00:00Z")
        XCTAssertEqual(
            DateBucketing.daysCovered(from: from, to: to, in: nyc),
            ["2024-03-09", "2024-03-10", "2024-03-11"]
        )
    }

    func test_daysCovered_emptyWhenFromAfterTo() {
        let from = iso("2024-06-17T10:00:00Z")
        let to = iso("2024-06-15T10:00:00Z")
        XCTAssertEqual(DateBucketing.daysCovered(from: from, to: to, in: utc), [])
    }
}
