import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class NullStore: HealthStoreAuthorizing, @unchecked Sendable {
    var isHealthDataAvailable: Bool { true }
    func requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?) async throws {}
    func execute(_ query: HKQuery) {}
    func stop(_ query: HKQuery) {}
    func cumulativeSum(of quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double? { nil }
}

private func sample(
    _ categoryID: String,
    value: Double,
    unit: String,
    at start: Date = Date(timeIntervalSince1970: 1_700_000_000)
) -> QuantitySampleDTO {
    QuantitySampleDTO(
        categoryID: categoryID,
        startDate: start,
        endDate: start.addingTimeInterval(60),
        value: value,
        unit: unit,
        sourceName: "Test",
        sourceBundleID: "test.bundle"
    )
}

final class QuantityCategorySummarizationTests: XCTestCase {
    private let store = NullStore()

    func test_steps_sumsToIntTotal() {
        let cat = StepsCategory(store: store)
        let s = [
            sample("steps", value: 1200, unit: "count"),
            sample("steps", value: 300, unit: "count"),
            sample("steps", value: 12, unit: "count")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["total"], .int(1512))
        XCTAssertEqual(frag.unit, "count")
    }

    func test_distance_sumsKilometers() {
        let cat = DistanceWalkingRunningCategory(store: store)
        let s = [
            sample("distance_walking_running", value: 3.21, unit: "km"),
            sample("distance_walking_running", value: 1.04, unit: "km")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["total"], .double(4.25))
        XCTAssertEqual(frag.unit, "km")
    }

    func test_activeEnergy_sumsKilocalories() {
        let cat = ActiveEnergyCategory(store: store)
        let s = [
            sample("active_energy", value: 200.4, unit: "kcal"),
            sample("active_energy", value: 411.6, unit: "kcal")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["total"], .int(612))
        XCTAssertEqual(frag.unit, "kcal")
    }

    func test_restingHeartRate_takesLatestRounded() {
        let cat = RestingHeartRateCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s = [
            sample("resting_heart_rate", value: 62, unit: "count/min", at: base),
            sample("resting_heart_rate", value: 57.6, unit: "count/min", at: base.addingTimeInterval(3600)),
            sample("resting_heart_rate", value: 60, unit: "count/min", at: base.addingTimeInterval(1800))
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["value"], .int(58))
        XCTAssertEqual(frag.unit, "bpm")
    }

    func test_restingHeartRate_emptyProducesEmptyMetrics() {
        let cat = RestingHeartRateCategory(store: store)
        let frag = cat.summarize([])
        XCTAssertTrue(frag.metrics.isEmpty)
        XCTAssertEqual(frag.unit, "bpm")
    }

    func test_hrv_averagesRoundedToInt() {
        let cat = HRVCategory(store: store)
        let s = [
            sample("hrv_sdnn", value: 40, unit: "ms"),
            sample("hrv_sdnn", value: 50, unit: "ms"),
            sample("hrv_sdnn", value: 52, unit: "ms")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["avg"], .int(47))
        XCTAssertEqual(frag.metrics["sample_count"], .int(3))
        XCTAssertEqual(frag.unit, "ms")
    }

    func test_hrv_countsMeasurementsEvenWhenValuesAreIdentical() {
        let cat = HRVCategory(store: store)
        for count in [1, 2, 20] {
            let samples = (0..<count).map { _ in sample("hrv_sdnn", value: 47, unit: "ms") }
            let frag = cat.summarize(samples)
            XCTAssertEqual(frag.metrics["avg"], .int(47))
            XCTAssertEqual(frag.metrics["sample_count"], .int(count))
        }
    }

    func test_hrv_emptyProducesEmptyMetrics() {
        let frag = HRVCategory(store: store).summarize([])
        XCTAssertTrue(frag.metrics.isEmpty)
        XCTAssertEqual(frag.unit, "ms")
    }

    func test_hrv_summaryReachesTelegramAndJSON() throws {
        var snapshot = DailySnapshot(
            date: Date(timeIntervalSince1970: 1_700_000_000), timezone: "Europe/Lisbon",
            generatedAt: Date(), deviceName: "Test", appVersion: "1.0"
        )
        snapshot.summaries["hrv_sdnn"] = HRVCategory(store: store).summarize([
            sample("hrv_sdnn", value: 40, unit: "ms"),
            sample("hrv_sdnn", value: 54, unit: "ms")
        ])
        let message = SummaryMarkdownSerializer().serialize(snapshot, flavor: .telegramV2)
        XCTAssertTrue(message.contains("47 ms · 2 measurements"))

        let data = try SummaryJSONSerializer().serialize(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metrics = try XCTUnwrap(json["metrics"] as? [String: Any])
        let hrv = try XCTUnwrap(metrics["hrv_sdnn"] as? [String: Any])
        XCTAssertEqual(hrv["avg"] as? Int, 47)
        XCTAssertEqual(hrv["sample_count"] as? Int, 2)
        XCTAssertEqual(hrv["unit"] as? String, "ms")
        XCTAssertEqual(json["schema_version"] as? String, "1.0")
    }

    func test_vo2Max_takesLatestRoundedOneDecimal() {
        let cat = VO2MaxCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s = [
            sample("vo2_max", value: 45.34, unit: "mL/kg*min", at: base),
            sample("vo2_max", value: 48.27, unit: "mL/kg*min", at: base.addingTimeInterval(86400))
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["value"], .double(48.3))
        XCTAssertEqual(frag.unit, "ml/kg·min")
    }

    func test_bodyMass_takesLatestRoundedOneDecimal() {
        let cat = BodyMassCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s = [
            sample("body_mass", value: 74.7, unit: "kg", at: base),
            sample("body_mass", value: 74.23, unit: "kg", at: base.addingTimeInterval(86400))
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["value"], .double(74.2))
        XCTAssertEqual(frag.unit, "kg")
    }

    func test_allCategoriesHaveStableIds() {
        XCTAssertEqual(StepsCategory(store: store).id, "steps")
        XCTAssertEqual(DistanceWalkingRunningCategory(store: store).id, "distance_walking_running")
        XCTAssertEqual(ActiveEnergyCategory(store: store).id, "active_energy")
        XCTAssertEqual(RestingHeartRateCategory(store: store).id, "resting_heart_rate")
        XCTAssertEqual(HRVCategory(store: store).id, "hrv_sdnn")
        XCTAssertEqual(VO2MaxCategory(store: store).id, "vo2_max")
        XCTAssertEqual(BodyMassCategory(store: store).id, "body_mass")
    }
}
