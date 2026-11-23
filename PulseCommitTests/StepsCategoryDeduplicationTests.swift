import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

/// Stub store that records how it was called. `execute` is intentionally a no-op so any
/// path that issues a raw `HKSampleQuery` produces zero samples — this lets us assert
/// that the summary path uses HKStatisticsQuery (via `cumulativeSum`), not raw samples.
final class StubStatisticsHealthStore: HealthStoreAuthorizing, @unchecked Sendable {
    var isHealthDataAvailable: Bool { true }
    var cumulativeSumValue: Double?
    private(set) var cumulativeSumCallCount = 0
    private(set) var lastQuantityTypeIdentifier: String?
    private(set) var executeCallCount = 0

    init(cumulativeSumValue: Double?) {
        self.cumulativeSumValue = cumulativeSumValue
    }

    func requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?) async throws {}
    func execute(_ query: HKQuery) { executeCallCount += 1 }
    func stop(_ query: HKQuery) {}

    func cumulativeSum(of quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double? {
        cumulativeSumCallCount += 1
        lastQuantityTypeIdentifier = quantityType.identifier
        return cumulativeSumValue
    }
}

final class StepsCategoryDeduplicationTests: XCTestCase {
    private let from = Date(timeIntervalSince1970: 1_715_731_200)
    private let to = Date(timeIntervalSince1970: 1_715_817_600)

    func test_fetchSummarySamples_usesHKStatisticsQuery_notRawSampleQuery() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 23456)
        let cat = StepsCategory(store: store)

        let samples = try await cat.fetchSummarySamples(from: from, to: to)

        XCTAssertEqual(store.cumulativeSumCallCount, 1, "Summary path must use HKStatisticsQuery (cumulativeSum), not HKSampleQuery")
        XCTAssertEqual(store.executeCallCount, 0, "No HKSampleQuery should be executed for the summary path")
        XCTAssertEqual(store.lastQuantityTypeIdentifier, HKQuantityTypeIdentifier.stepCount.rawValue)
        XCTAssertEqual(samples.count, 1, "Cumulative summary returns one aggregated DTO")
        let dto = try XCTUnwrap(samples.first as? QuantitySampleDTO)
        XCTAssertEqual(dto.value, 23456, accuracy: 0.001)
        XCTAssertEqual(dto.categoryID, "steps")
    }

    func test_summarize_overAggregatedDTO_producesDedupedTotal() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 23456)
        let cat = StepsCategory(store: store)

        let samples = try await cat.fetchSummarySamples(from: from, to: to)
        let fragment = cat.summarize(samples)

        XCTAssertEqual(fragment.metrics["total"], .int(23456), "Steps total should be the HealthKit deduplicated sum, not 2x")
        XCTAssertEqual(fragment.unit, "count")
    }

    func test_fetchSummarySamples_emptyHealthKit_returnsNoSamples() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: nil)
        let cat = StepsCategory(store: store)

        let samples = try await cat.fetchSummarySamples(from: from, to: to)

        XCTAssertTrue(samples.isEmpty, "When HealthKit returns no data, summary returns no samples (so live-preview shows '—')")
    }

    func test_activeEnergy_usesStatisticsQueryForSummary() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 412.7)
        let cat = ActiveEnergyCategory(store: store)

        let samples = try await cat.fetchSummarySamples(from: from, to: to)

        XCTAssertEqual(store.cumulativeSumCallCount, 1)
        XCTAssertEqual(store.lastQuantityTypeIdentifier, HKQuantityTypeIdentifier.activeEnergyBurned.rawValue)
        let dto = try XCTUnwrap(samples.first as? QuantitySampleDTO)
        XCTAssertEqual(dto.value, 412.7, accuracy: 0.001)
    }

    func test_distance_usesStatisticsQueryForSummary() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 4.25)
        let cat = DistanceWalkingRunningCategory(store: store)

        let samples = try await cat.fetchSummarySamples(from: from, to: to)

        XCTAssertEqual(store.cumulativeSumCallCount, 1)
        XCTAssertEqual(store.lastQuantityTypeIdentifier, HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue)
        let fragment = cat.summarize(samples)
        XCTAssertEqual(fragment.metrics["total"], .double(4.25))
    }

    func test_activityRings_usesStatisticsQueryForBothStandAndExercise() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 30)
        let cat = ActivityRingsCategory(store: store)

        _ = try await cat.fetchSummarySamples(from: from, to: to)

        XCTAssertEqual(store.cumulativeSumCallCount, 2, "Both standTime and exerciseTime go through HKStatisticsQuery")
    }

    func test_nutrition_usesStatisticsQueryForEachSubtype() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 100)
        let cat = NutritionCategory(store: store)

        _ = try await cat.fetchSummarySamples(from: from, to: to)

        XCTAssertEqual(store.cumulativeSumCallCount, NutritionCategory.subtypes.count)
    }

    /// Regression for the original bug: user's real iPhone steps were 23 000 but the
    /// tile showed 46 592 — exactly 2x because iPhone + Apple Watch each wrote samples
    /// and the old summary path summed them. With HKStatisticsQuery the doubling is
    /// impossible because HealthKit picks one source per overlap.
    func test_regression_homeTileNoLongerDoublesIPhoneWatchOverlap() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 23000)
        let cat = StepsCategory(store: store)

        let samples = try await cat.fetchSummarySamples(from: from, to: to)
        let fragment = cat.summarize(samples)

        XCTAssertEqual(fragment.metrics["total"], .int(23000))
        XCTAssertNotEqual(fragment.metrics["total"], .int(46000))
    }
}

final class HKQuantitySampleMappingCumulativeTotalTests: XCTestCase {
    private let from = Date(timeIntervalSince1970: 1_715_731_200)
    private let to = Date(timeIntervalSince1970: 1_715_817_600)

    func test_fetchCumulativeTotal_packagesStatisticsValueIntoSingleDTO() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: 12345)
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        let samples = try await fetchCumulativeTotal(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.count(),
            categoryID: "steps"
        )

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].value, 12345, accuracy: 0.001)
        XCTAssertEqual(samples[0].categoryID, "steps")
        XCTAssertEqual(samples[0].startDate, from)
        XCTAssertEqual(samples[0].endDate, to)
        XCTAssertEqual(samples[0].unit, "count")
    }

    func test_fetchCumulativeTotal_returnsEmptyWhenNoData() async throws {
        let store = StubStatisticsHealthStore(cumulativeSumValue: nil)
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        let samples = try await fetchCumulativeTotal(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.count(),
            categoryID: "steps"
        )

        XCTAssertTrue(samples.isEmpty)
    }
}
