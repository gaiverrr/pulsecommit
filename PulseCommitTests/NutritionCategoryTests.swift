import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class NutritionCategoryTests: XCTestCase {
    private let store = NullStore()

    private func sample(_ subId: String, value: Double) -> QuantitySampleDTO {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return QuantitySampleDTO(
            categoryID: subId,
            startDate: start,
            endDate: start.addingTimeInterval(60),
            value: value,
            unit: "mixed",
            sourceName: "Test",
            sourceBundleID: "test.bundle"
        )
    }

    func test_summarize_aggregatesEachSubtype() {
        let cat = NutritionCategory(store: store)
        let samples = [
            sample("nutrition.energy", value: 250),
            sample("nutrition.energy", value: 350.5),
            sample("nutrition.protein", value: 12.2),
            sample("nutrition.protein", value: 7.8),
            sample("nutrition.carbs", value: 40),
            sample("nutrition.fat", value: 9.4),
            sample("nutrition.fiber", value: 3.2),
            sample("nutrition.sugar", value: 11.1),
            sample("nutrition.water", value: 500),
            sample("nutrition.water", value: 250),
            sample("nutrition.caffeine", value: 95)
        ]
        let frag = cat.summarize(samples)

        XCTAssertEqual(frag.metrics["energy_kcal"], .double(600.5))
        XCTAssertEqual(frag.metrics["protein_g"], .double(20.0))
        XCTAssertEqual(frag.metrics["carbs_g"], .double(40.0))
        XCTAssertEqual(frag.metrics["fat_g"], .double(9.4))
        XCTAssertEqual(frag.metrics["fiber_g"], .double(3.2))
        XCTAssertEqual(frag.metrics["sugar_g"], .double(11.1))
        XCTAssertEqual(frag.metrics["water_ml"], .double(750.0))
        XCTAssertEqual(frag.metrics["caffeine_mg"], .double(95.0))
        XCTAssertEqual(frag.unit, "mixed")
    }

    func test_summarize_emptyProducesZeroes() {
        let cat = NutritionCategory(store: store)
        let frag = cat.summarize([])
        for sub in NutritionCategory.subtypes {
            XCTAssertEqual(frag.metrics[sub.metricKey], .double(0.0), "expected zero for \(sub.metricKey)")
        }
    }

    func test_subtypes_eightDistinctMetricKeys() {
        XCTAssertEqual(NutritionCategory.subtypes.count, 8)
        let keys = Set(NutritionCategory.subtypes.map(\.metricKey))
        XCTAssertEqual(keys.count, 8)
    }

    func test_id_isStable() {
        XCTAssertEqual(NutritionCategory(store: store).id, "nutrition")
    }
}
