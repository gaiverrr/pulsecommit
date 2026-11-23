import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class HomeLivePreviewModelTests: XCTestCase {
    private struct StubCategory: HealthCategory, @unchecked Sendable {
        let id: String
        let displayName: String
        let samples: [any SampleDTO]
        let fragment: SummaryFragment
        func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { samples }
        func summarize(_ samples: [any SampleDTO]) -> SummaryFragment { fragment }
    }

    private func sample(category: String, value: Double, unit: String) -> QuantitySampleDTO {
        QuantitySampleDTO(
            categoryID: category,
            startDate: Date(),
            endDate: Date(),
            value: value,
            unit: unit,
            sourceName: "test",
            sourceBundleID: "com.test"
        )
    }

    private func categorySample(category: String, value: Int) -> CategorySampleDTO {
        CategorySampleDTO(
            categoryID: category,
            startDate: Date(),
            endDate: Date(),
            value: value,
            sourceName: "test",
            sourceBundleID: "com.test"
        )
    }

    private func workoutSample() -> WorkoutSampleDTO {
        WorkoutSampleDTO(
            categoryID: "workouts",
            sourceName: "test",
            sourceBundleID: "com.test",
            workout: WorkoutDTO(
                id: "w1",
                type: .outdoorRun,
                startDate: Date(),
                endDate: Date().addingTimeInterval(600),
                durationMinutes: 10,
                distanceKm: 2.0,
                activeEnergyKcal: 100,
                avgHeartRate: nil,
                maxHeartRate: nil,
                route: []
            )
        )
    }

    func test_emptySamples_leavesValuesNil() async {
        let registry = CategoryRegistry(categories: [
            StubCategory(id: "steps", displayName: "Steps", samples: [], fragment: SummaryFragment()),
            StubCategory(id: "active_energy", displayName: "Active", samples: [], fragment: SummaryFragment()),
            StubCategory(id: "sleep", displayName: "Sleep", samples: [], fragment: SummaryFragment()),
            StubCategory(id: "workouts", displayName: "Workouts", samples: [], fragment: SummaryFragment())
        ])
        let model = HomeLivePreviewModel(registry: registry)
        await model.refresh()
        XCTAssertNil(model.todaySteps)
        XCTAssertNil(model.todayActiveKcal)
        XCTAssertNil(model.todaySleepMinutes)
        XCTAssertNil(model.todayWorkoutCount)
    }

    func test_populatedSamples_exposeValues() async {
        let stepSample = sample(category: "steps", value: 1234, unit: "count")
        let energySample = sample(category: "active_energy", value: 250, unit: "kcal")
        let sleep1 = categorySample(category: "sleep", value: 0)
        let workout = workoutSample()

        let registry = CategoryRegistry(categories: [
            StubCategory(
                id: "steps",
                displayName: "Steps",
                samples: [stepSample],
                fragment: SummaryFragment(metrics: ["total": .int(1234)], unit: "count")
            ),
            StubCategory(
                id: "active_energy",
                displayName: "Active",
                samples: [energySample],
                fragment: SummaryFragment(metrics: ["total": .int(250)], unit: "kcal")
            ),
            StubCategory(
                id: "sleep",
                displayName: "Sleep",
                samples: [sleep1],
                fragment: SummaryFragment(metrics: ["duration_minutes": .int(420)], unit: "min")
            ),
            StubCategory(
                id: "workouts",
                displayName: "Workouts",
                samples: [workout],
                fragment: SummaryFragment(metrics: ["count": .int(1)], unit: "workouts")
            )
        ])
        let model = HomeLivePreviewModel(registry: registry)
        await model.refresh()
        XCTAssertEqual(model.todaySteps, 1234)
        XCTAssertEqual(model.todayActiveKcal, 250)
        XCTAssertEqual(model.todaySleepMinutes, 420)
        XCTAssertEqual(model.todayWorkoutCount, 1)
    }

    func test_formatters() {
        XCTAssertEqual(HomeLivePreviewModel.formatSteps(nil), "—")
        XCTAssertEqual(HomeLivePreviewModel.formatSteps(12483), "12 483")
        XCTAssertEqual(HomeLivePreviewModel.formatKcal(250.4), "250")
        XCTAssertEqual(HomeLivePreviewModel.formatKcal(nil), "—")
        XCTAssertEqual(HomeLivePreviewModel.formatSleep(420), "7h 0m")
        XCTAssertEqual(HomeLivePreviewModel.formatSleep(nil), "—")
        XCTAssertEqual(HomeLivePreviewModel.formatWorkouts(3), "3")
        XCTAssertEqual(HomeLivePreviewModel.formatWorkouts(nil), "—")
    }
}
