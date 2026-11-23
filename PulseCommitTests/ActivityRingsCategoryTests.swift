import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class ActivityRingsCategoryTests: XCTestCase {
    private let store = NullStore()

    private func sample(_ subId: String, value: Double) -> QuantitySampleDTO {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return QuantitySampleDTO(
            categoryID: subId,
            startDate: start,
            endDate: start.addingTimeInterval(60),
            value: value,
            unit: "min",
            sourceName: "Test",
            sourceBundleID: "test.bundle"
        )
    }

    func test_summarize_aggregatesStandHoursAndExerciseMinutes() {
        let cat = ActivityRingsCategory(store: store)
        let s = [
            sample(ActivityRingsCategory.standSubId, value: 30),
            sample(ActivityRingsCategory.standSubId, value: 90),
            sample(ActivityRingsCategory.standSubId, value: 60),
            sample(ActivityRingsCategory.exerciseSubId, value: 12),
            sample(ActivityRingsCategory.exerciseSubId, value: 18.4)
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stand_hours"], .double(3.0))
        XCTAssertEqual(frag.metrics["exercise_minutes"], .int(30))
    }

    func test_summarize_emptyProducesZeroes() {
        let cat = ActivityRingsCategory(store: store)
        let frag = cat.summarize([])
        XCTAssertEqual(frag.metrics["stand_hours"], .double(0.0))
        XCTAssertEqual(frag.metrics["exercise_minutes"], .int(0))
    }

    func test_id_isStable() {
        XCTAssertEqual(ActivityRingsCategory(store: store).id, "activity_rings")
    }
}
