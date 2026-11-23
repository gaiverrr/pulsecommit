import XCTest
@testable import HealthCore

final class AutomaticWorkoutMessageRendererTests: XCTestCase {
    func test_render_buildsOneBoundedWorkoutOnlyMarkdownMessage() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-24T09:00:00Z"))
        let intervals = (0..<6).map { index in
            WorkoutRecordedIntervalDTO(
                kind: .lap,
                startDate: start.addingTimeInterval(Double(index) * 60),
                endDate: start.addingTimeInterval(Double(index + 1) * 60),
                durationSeconds: 60
            )
        }
        let workout = WorkoutDTO(
            id: "private-healthkit-uuid",
            type: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(1_845.4),
            durationMinutes: 30,
            distanceKm: 5.01,
            activeEnergyKcal: 412.4,
            avgHeartRate: 151.2,
            maxHeartRate: 174.7,
            route: [RoutePointDTO(time: start, latitude: 38.72, longitude: -9.14, elevationMeters: 2)],
            heartRateZones: WorkoutHeartRateZones(
                lowerBoundsBPM: [100, 120, 140, 160],
                secondsByZone: [10, 20, 30, 40, 50],
                activeSeconds: 1_845.4,
                method: "custom"
            ),
            durationSeconds: 1_845.4,
            distanceMeters: 5_010,
            recordedIntervals: intervals
        )

        let message = AutomaticWorkoutMessageRenderer().render(
            workout: workout,
            timeZoneIdentifier: "Europe/Lisbon"
        )

        XCTAssertTrue(message.hasPrefix("🏁 *Workout finished*"))
        XCTAssertTrue(message.contains("Outdoor Run"))
        XCTAssertTrue(message.contains("Duration: 30m 45\\.4s"))
        XCTAssertTrue(message.contains("Avg pace: 6:08/km"))
        XCTAssertTrue(message.contains("2 more laps omitted"))
        XCTAssertFalse(message.contains("JSON"))
        XCTAssertFalse(message.contains("private-healthkit-uuid"))
        XCTAssertFalse(message.contains("38.72"))
        XCTAssertFalse(message.contains("HR zones"))
        XCTAssertLessThanOrEqual(message.utf8.count, AutomaticWorkoutMessageRenderer.telegramTextLimit)
        if let directory = ProcessInfo.processInfo.environment["PULSECOMMIT_ARTIFACT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("synthetic-workout-message.md")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try message.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func test_render_omitsInvalidOptionalValuesAndUsesCyclingSpeed() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let workout = WorkoutDTO(
            id: "id",
            type: .outdoorCycling,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            durationMinutes: 60,
            distanceKm: .infinity,
            activeEnergyKcal: -.infinity,
            avgHeartRate: .nan,
            maxHeartRate: -1,
            route: [],
            durationSeconds: 3_600,
            distanceMeters: 25_000
        )

        let message = AutomaticWorkoutMessageRenderer().render(workout: workout, timeZoneIdentifier: "UTC")

        XCTAssertTrue(message.contains("Avg speed: 25 km/h"))
        XCTAssertFalse(message.contains("Distance:"))
        XCTAssertFalse(message.contains("Heart rate:"))
        XCTAssertFalse(message.lowercased().contains("nan"))
        XCTAssertFalse(message.lowercased().contains("inf"))
    }

    func test_render_hugeFiniteMeasurementsNeverOverflowIntegerFormatting() {
        let start = Date(timeIntervalSince1970: 1_760_000_000)
        let workout = WorkoutDTO(
            id: "id",
            type: .outdoorRun,
            startDate: start,
            endDate: start.addingTimeInterval(60),
            durationMinutes: 1,
            distanceKm: .greatestFiniteMagnitude,
            activeEnergyKcal: Double(Int.max),
            avgHeartRate: .greatestFiniteMagnitude,
            maxHeartRate: Double(Int.max),
            route: [],
            durationSeconds: .greatestFiniteMagnitude,
            distanceMeters: 1
        )

        let message = AutomaticWorkoutMessageRenderer().render(workout: workout, timeZoneIdentifier: "UTC")

        XCTAssertTrue(message.contains("Duration: 1 min"))
        XCTAssertFalse(message.contains("Heart rate:"))
        XCTAssertLessThanOrEqual(message.utf8.count, AutomaticWorkoutMessageRenderer.telegramTextLimit)
    }
}
