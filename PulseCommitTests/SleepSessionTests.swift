import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class SleepSessionTests: XCTestCase {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func stage(_ value: HKCategoryValueSleepAnalysis, _ start: String, _ end: String) -> CategorySampleDTO {
        CategorySampleDTO(categoryID: "sleep", startDate: date(start), endDate: date(end),
                          value: value.rawValue, sourceName: "Watch", sourceBundleID: "watch")
    }

    func test_overnightStagesStayTogetherAndBelongToWakeDate() throws {
        let samples = [
            stage(.asleepCore, "2026-05-13T22:00:00Z", "2026-05-14T02:00:00Z"),
            stage(.awake, "2026-05-14T02:00:00Z", "2026-05-14T02:20:00Z"),
            stage(.asleepREM, "2026-05-14T02:20:00Z", "2026-05-14T06:00:00Z")
        ]
        let sessions = SleepSessionSample.make(from: samples)
        let session = try XCTUnwrap(sessions.first)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(session.startDate, date("2026-05-14T06:00:00Z"))
        let summary = SleepCategory(store: NullStore()).summarize(sessions)
        XCTAssertEqual(summary.metrics["duration_minutes"], .int(460))
        XCTAssertEqual(summary.metrics["stage_awake"], .int(20))
        XCTAssertEqual(summary.metrics["sleep_start"], .string("2026-05-13T22:00:00Z"))
        XCTAssertEqual(summary.metrics["sleep_end"], .string("2026-05-14T06:00:00Z"))
    }

    func test_napDoesNotReplaceMainSleepTimesOrConnectTwoNights() {
        let samples = [
            stage(.asleepCore, "2026-05-13T22:00:00Z", "2026-05-14T06:00:00Z"),
            stage(.asleepCore, "2026-05-14T14:00:00Z", "2026-05-14T14:30:00Z"),
            stage(.asleepCore, "2026-05-14T22:00:00Z", "2026-05-15T06:00:00Z")
        ]
        let sessions = SleepSessionSample.make(from: samples)
        XCTAssertEqual(sessions.count, 3)
        let summary = SleepCategory(store: NullStore()).summarize(Array(sessions.prefix(2)))
        XCTAssertEqual(summary.metrics["duration_minutes"], .int(510))
        XCTAssertEqual(summary.metrics["sleep_start"], .string("2026-05-13T22:00:00Z"))
        XCTAssertEqual(summary.metrics["sleep_end"], .string("2026-05-14T06:00:00Z"))
    }

    func test_inBedAndAwakeAloneDoNotInventSleepTimes() {
        let samples = [stage(.inBed, "2026-05-13T22:00:00Z", "2026-05-14T06:00:00Z")]
        XCTAssertTrue(SleepSessionSample.make(from: samples).isEmpty)
        let summary = SleepCategory(store: NullStore()).summarize(samples)
        XCTAssertNil(summary.metrics["sleep_start"])
        XCTAssertNil(summary.metrics["sleep_end"])
    }

    func test_respiratorySummaryOnlyIncludesMeasurementsDuringRecordedSleep() {
        let sessions = SleepSessionSample.make(from: [
            stage(.asleepCore, "2026-05-13T22:00:00Z", "2026-05-14T02:00:00Z"),
            stage(.awake, "2026-05-14T02:00:00Z", "2026-05-14T03:00:00Z"),
            stage(.asleepREM, "2026-05-14T03:00:00Z", "2026-05-14T06:00:00Z")
        ])
        let rates = [("2026-05-13T23:00:00Z", 14.0), ("2026-05-14T04:00:00Z", 15.0),
                     ("2026-05-14T02:30:00Z", 30.0), ("2026-05-14T12:00:00Z", 40.0)].map { time, value in
            QuantitySampleDTO(categoryID: "respiratory_rate", startDate: date(time), endDate: date(time),
                              value: value, unit: "count/min", sourceName: "Watch", sourceBundleID: "watch")
        }
        let samples = RespiratoryRateCategory.sleepSamples(rates, sessions: sessions)
        XCTAssertEqual(samples.count, 2)
        XCTAssertTrue(samples.allSatisfy { $0.startDate == date("2026-05-14T06:00:00Z") })
        let summary = RespiratoryRateCategory(store: NullStore()).summarize(samples)
        XCTAssertEqual(summary.metrics["sleep_avg"], .double(14.5))
        XCTAssertEqual(summary.metrics["sample_count"], .int(2))
        XCTAssertTrue(RespiratoryRateCategory(store: NullStore()).summarize([]).metrics.isEmpty)
    }

    func test_normalizerBucketsOvernightSessionsByLocalWakeDateAcrossDST() async throws {
        let samples = [
            stage(.asleepCore, "2026-03-28T23:00:00Z", "2026-03-29T06:00:00Z"),
            stage(.asleepCore, "2026-03-29T22:00:00Z", "2026-03-30T06:00:00Z")
        ]
        let category = SessionCategory(samples: SleepSessionSample.make(from: samples))
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [category]), timezone: TimeZone(identifier: "Europe/Lisbon")!,
            deviceName: "Test", appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: date("2026-03-29T00:00:00Z"), to: date("2026-03-30T23:00:00Z")
        )
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].summaries["sleep"]?.metrics["duration_minutes"], .int(420))
        XCTAssertEqual(snapshots[1].summaries["sleep"]?.metrics["duration_minutes"], .int(480))
        XCTAssertEqual(snapshots[0].summaries["sleep"]?.metrics["sleep_start"], .string("2026-03-28T23:00:00Z"))
    }
}

private struct SessionCategory: HealthCategory {
    let id = "sleep"
    let displayName = "Sleep"
    let samples: [SleepSessionSample]
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        samples.filter { $0.startDate >= from && $0.startDate < to }
    }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SleepCategory(store: NullStore()).summarize(samples)
    }
}
