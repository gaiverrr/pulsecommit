import XCTest
@testable import HealthCore

final class HeartRateZoneEstimatorTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 0)
    private func sample(_ seconds: Double, _ bpm: Double) -> QuantitySampleDTO {
        QuantitySampleDTO(categoryID: "heart_rate", startDate: start.addingTimeInterval(seconds),
                          endDate: start.addingTimeInterval(seconds), value: bpm, unit: "count/min",
                          sourceName: "Watch", sourceBundleID: "watch")
    }
    func test_configurationRequiresFourAscendingThresholds() {
        XCTAssertNotNil(HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160]))
        for invalid in [[], [100, 120], [100, 100, 140, 160], [120, 100, 140, 160], [0, 100, 140, 160], [100, 120, 140, 301]] {
            XCTAssertNil(HeartRateZoneConfiguration(lowerBoundsBPM: invalid))
        }
    }
    func test_boundariesAndTimeCoverage() throws {
        let result = try XCTUnwrap(HeartRateZoneEstimator.estimate(
            samples: [sample(0, 99), sample(10, 100), sample(20, 120), sample(30, 140), sample(40, 160)],
            configuration: HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!,
            workout: DateInterval(start: start, duration: 50), activeIntervals: [DateInterval(start: start, duration: 50)]
        ))
        XCTAssertEqual(result.secondsByZone, [10, 10, 10, 10, 10])
        XCTAssertEqual(result.coveredSeconds, 50)
        XCTAssertEqual(result.activeSeconds, 50)
    }
    func test_gapsAndPausesAreNotCountedAsMeasuredTime() throws {
        let result = try XCTUnwrap(HeartRateZoneEstimator.estimate(
            samples: [sample(0, 110), sample(300, 170)],
            configuration: HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!,
            workout: DateInterval(start: start, duration: 600),
            activeIntervals: [DateInterval(start: start, duration: 10), DateInterval(start: start.addingTimeInterval(300), duration: 300)]
        ))
        XCTAssertEqual(result.secondsByZone, [0, 10, 0, 0, 30])
        XCTAssertEqual(result.coveredSeconds, 40)
        XCTAssertEqual(result.activeSeconds, 310)
    }
    func test_duplicateTimestampsAndOverlappingActiveIntervalsDoNotDoubleCount() throws {
        let result = try XCTUnwrap(HeartRateZoneEstimator.estimate(
            samples: [sample(0, 110), sample(0, 130), sample(60, 170)],
            configuration: HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!,
            workout: DateInterval(start: start, duration: 30),
            activeIntervals: [DateInterval(start: start, duration: 30), DateInterval(start: start, duration: 30)]
        ))
        XCTAssertEqual(result.secondsByZone, [0, 0, 30, 0, 0])
        XCTAssertEqual(result.activeSeconds, 30)
    }
    func test_noReadingsProducesNoEstimate() {
        XCTAssertNil(HeartRateZoneEstimator.estimate(
            samples: [sample(0, .nan), sample(10, -1)],
            configuration: HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!,
            workout: DateInterval(start: start, duration: 30), activeIntervals: [DateInterval(start: start, duration: 30)]
        ))
    }

    func test_resumeWaitsForFreshReadingEvenAfterShortPause() throws {
        let result = try XCTUnwrap(HeartRateZoneEstimator.estimate(
            samples: [sample(0, 110), sample(12, 170), sample(25, 130)],
            configuration: HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!,
            workout: DateInterval(start: start, duration: 40),
            activeIntervals: [DateInterval(start: start, duration: 10), DateInterval(start: start.addingTimeInterval(20), duration: 20)]
        ))
        XCTAssertEqual(result.secondsByZone, [0, 10, 15, 0, 0])
        XCTAssertEqual(result.coveredSeconds, 25)
        XCTAssertEqual(result.activeSeconds, 30)
    }
}
