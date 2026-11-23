import XCTest
import HealthCore
@testable import PulseCommit

final class DefaultRegistryFactoryTests: XCTestCase {
    func test_make_returnsAllMVPCategoriesInDocumentedOrder() {
        let registry = DefaultRegistryFactory.make(store: NullStore())
        XCTAssertEqual(registry.all.map(\.id), [
            "steps",
            "distance_walking_running",
            "heart_rate",
            "resting_heart_rate",
            "hrv_sdnn",
            "vo2_max",
            "active_energy",
            "activity_rings",
            "sleep",
            "respiratory_rate",
            "wrist_temperature",
            "workouts",
            "body_mass",
            "state_of_mind",
            "nutrition"
        ])
    }

    func test_make_lookupByIdResolvesEveryCategory() {
        let registry = DefaultRegistryFactory.make(store: NullStore())
        for id in registry.all.map(\.id) {
            XCTAssertNotNil(registry.category(withId: id), "missing category: \(id)")
        }
    }
}

final class HeartRateCategorySummarizationTests: XCTestCase {
    private let store = NullStore()

    private func hrSample(_ value: Double, at start: Date) -> QuantitySampleDTO {
        QuantitySampleDTO(
            categoryID: "heart_rate",
            startDate: start,
            endDate: start.addingTimeInterval(1),
            value: value,
            unit: "count/min",
            sourceName: "Test",
            sourceBundleID: "test.bundle"
        )
    }

    func test_emptyProducesEmptyMetrics() {
        let cat = HeartRateCategory(store: store)
        let frag = cat.summarize([])
        XCTAssertTrue(frag.metrics.isEmpty)
        XCTAssertEqual(frag.unit, "count/min")
    }

    func test_averagesAndMaxRoundedToInt() {
        let cat = HeartRateCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s = [
            hrSample(72, at: base),
            hrSample(118.4, at: base.addingTimeInterval(60)),
            hrSample(91.2, at: base.addingTimeInterval(120))
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["avg"], .int(94))
        XCTAssertEqual(frag.metrics["max"], .int(118))
        XCTAssertEqual(frag.unit, "count/min")
    }

    func test_idAndDisplayName() {
        let cat = HeartRateCategory(store: store)
        XCTAssertEqual(cat.id, "heart_rate")
        XCTAssertEqual(cat.displayName, "Heart Rate")
    }
}
