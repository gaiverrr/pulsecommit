import XCTest
@testable import HealthCore

final class DailySnapshotTests: XCTestCase {
    func test_dailySnapshot_isCodable_andDateIsoFormatted() throws {
        var snapshot = DailySnapshot(
            date: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-14T00:00:00Z")),
            timezone: "Europe/Lisbon",
            generatedAt: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-05-14T22:30:12Z")),
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snapshot.unavailableCategories = ["nutrition"]
        snapshot.summaries["steps"] = SummaryFragment(
            metrics: ["total": .int(12483)],
            unit: "count"
        )
        snapshot.workouts = []

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DailySnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, "1.0")
    }

    func test_dailySnapshot_roundTrip_includesWorkoutsAndStateOfMind() throws {
        var snapshot = DailySnapshot(
            date: Date(timeIntervalSince1970: 1_715_644_800),
            timezone: "UTC",
            generatedAt: Date(timeIntervalSince1970: 1_715_731_200),
            deviceName: "iPhone",
            appVersion: "1.0.0"
        )
        let workout = WorkoutDTO(
            id: "7f3a",
            type: .outdoorRun,
            startDate: Date(timeIntervalSince1970: 1_715_650_000),
            endDate: Date(timeIntervalSince1970: 1_715_652_280),
            durationMinutes: 38,
            distanceKm: 6.2,
            activeEnergyKcal: 410,
            avgHeartRate: 152,
            maxHeartRate: 174,
            route: []
        )
        snapshot.workouts = [workout]
        snapshot.summaries["steps"] = SummaryFragment(metrics: ["total": .int(8400)], unit: "count")
        snapshot.summaries["vo2_max"] = SummaryFragment(metrics: ["value": .double(48.2)], unit: "ml/kg/min")
        snapshot.stateOfMind = [
            StateOfMindEntryDTO(
                time: Date(timeIntervalSince1970: 1_715_673_300),
                valence: 0.4,
                labels: ["calm", "focused"]
            )
        ]

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DailySnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }
}
