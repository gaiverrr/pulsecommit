import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class HomeLivePreviewModelYesterdayTests: XCTestCase {
    private final class WindowAwareCategory: HealthCategory, @unchecked Sendable {
        let id: String
        let displayName: String
        let stepsByOffset: [Int: Int]
        init(id: String, displayName: String, stepsByOffset: [Int: Int]) {
            self.id = id
            self.displayName = displayName
            self.stepsByOffset = stepsByOffset
        }
        func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
            // Use the duration-in-days from `from` relative to a fixed anchor to choose.
            // Simpler: use the "to" date hour; today window has hour > 0, yesterday window has to at 00:00.
            let cal = Calendar(identifier: .gregorian)
            let hour = cal.component(.hour, from: to)
            let value = stepsByOffset[hour] ?? 0
            if value == 0 { return [] }
            return [
                QuantitySampleDTO(
                    categoryID: id,
                    startDate: from,
                    endDate: to,
                    value: Double(value),
                    unit: "count",
                    sourceName: "test",
                    sourceBundleID: "com.test"
                )
            ]
        }
        func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
            let total = samples.compactMap { ($0 as? QuantitySampleDTO)?.value }.reduce(0, +)
            return SummaryFragment(metrics: ["total": .int(Int(total))], unit: "count")
        }
    }

    private final class WorkoutsStub: HealthCategory, @unchecked Sendable {
        let id = "workouts"
        let displayName = "Workouts"
        let countByHour: [Int: Int]
        init(_ counts: [Int: Int]) { self.countByHour = counts }
        func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
            let cal = Calendar(identifier: .gregorian)
            let hour = cal.component(.hour, from: to)
            let count = countByHour[hour] ?? 0
            return (0..<count).map { _ in
                WorkoutSampleDTO(
                    categoryID: id,
                    sourceName: "t",
                    sourceBundleID: "c",
                    workout: WorkoutDTO(
                        id: UUID().uuidString,
                        type: .outdoorRun,
                        startDate: from,
                        endDate: to,
                        durationMinutes: 30,
                        distanceKm: nil,
                        activeEnergyKcal: nil,
                        avgHeartRate: nil,
                        maxHeartRate: nil,
                        route: []
                    )
                )
            }
        }
        func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
            SummaryFragment(metrics: ["count": .int(samples.count)], unit: "workouts")
        }
    }

    func test_yesterdayWindowFetchesYesterdayValues() async {
        // Anchor "now" at 14:00 — today-window has `to` hour=14, yesterday-window has `to` hour=0.
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 14))!

        let steps = WindowAwareCategory(
            id: "steps",
            displayName: "Steps",
            stepsByOffset: [14: 5000, 0: 9000]
        )
        let registry = CategoryRegistry(categories: [
            steps,
            WorkoutsStub([14: 0, 0: 0])
        ])
        let model = HomeLivePreviewModel(registry: registry, calendar: cal, now: { now })
        await model.refresh(mode: .today)
        XCTAssertEqual(model.todaySteps, 5000)
        XCTAssertEqual(model.currentMode, .today)
        XCTAssertEqual(model.displaySteps, 5000)

        await model.refresh(mode: .yesterday)
        XCTAssertEqual(model.yesterdaySteps, 9000)
        XCTAssertEqual(model.currentMode, .yesterday)
        XCTAssertEqual(model.displaySteps, 9000)
        // Today values remain accessible after switching mode.
        XCTAssertEqual(model.todaySteps, 5000)
    }
}
