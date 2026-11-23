import XCTest
import HealthCore
@testable import PulseCommit

final class WorkoutsCategorySummarizationTests: XCTestCase {
    private let store = NullStore()

    private func sample(id: String, type: WorkoutDTO.WorkoutType = .outdoorRun) -> WorkoutSampleDTO {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = WorkoutDTO(
            id: id,
            type: type,
            startDate: start,
            endDate: start.addingTimeInterval(1800),
            durationMinutes: 30,
            distanceKm: 5.0,
            activeEnergyKcal: 300,
            avgHeartRate: nil,
            maxHeartRate: nil,
            route: []
        )
        return WorkoutSampleDTO(
            categoryID: "workouts",
            sourceName: "Apple Watch",
            sourceBundleID: "com.apple.health",
            workout: workout
        )
    }

    func test_id_isStable() {
        XCTAssertEqual(WorkoutsCategory(store: store).id, "workouts")
    }

    func test_summarize_countsWorkouts() {
        let cat = WorkoutsCategory(store: store)
        let s: [any SampleDTO] = [sample(id: "A"), sample(id: "B", type: .yoga), sample(id: "C")]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["count"], .int(3))
        XCTAssertEqual(frag.unit, "workouts")
    }

    func test_summarize_emptyProducesZeroCount() {
        let cat = WorkoutsCategory(store: store)
        let frag = cat.summarize([])
        XCTAssertEqual(frag.metrics["count"], .int(0))
    }
}
