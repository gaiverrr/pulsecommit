import XCTest
@testable import HealthCore

final class WorkoutFilesSerializerTests: XCTestCase {
    private func decode(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testProducesJSONForEveryWorkoutAndGPXOnlyForRouted() throws {
        let routed = WorkoutDTO(
            id: "7f3a",
            type: .outdoorRun,
            startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
            endDate: SampleFixtures.iso("2026-05-14T07:38:00Z"),
            durationMinutes: 38,
            distanceKm: 6.2,
            activeEnergyKcal: 410,
            avgHeartRate: 152,
            maxHeartRate: 174,
            route: [
                RoutePointDTO(
                    time: SampleFixtures.iso("2026-05-14T07:00:00Z"),
                    latitude: 38.72, longitude: -9.13, elevationMeters: 10
                )
            ]
        )
        let strength = WorkoutDTO(
            id: "8b21",
            type: .functionalStrengthTraining,
            startDate: SampleFixtures.iso("2026-05-14T18:00:00Z"),
            endDate: SampleFixtures.iso("2026-05-14T18:45:00Z"),
            durationMinutes: 45,
            distanceKm: nil,
            activeEnergyKcal: 280,
            avgHeartRate: 118,
            maxHeartRate: 140,
            route: []
        )

        let files = try WorkoutFilesSerializer().serialize(workouts: [routed, strength])
        let paths = files.map(\.path).sorted()
        XCTAssertEqual(paths, [
            "routes/7f3a-outdoor-run.gpx",
            "workouts/7f3a-outdoor-run.json",
            "workouts/8b21-functional-strength-training.json"
        ])
    }

    func testWorkoutJSONCarriesSchemaVersionAndMetadata() throws {
        let workout = WorkoutDTO(
            id: "7f3a",
            type: .outdoorRun,
            startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
            endDate: SampleFixtures.iso("2026-05-14T07:38:00Z"),
            durationMinutes: 38,
            distanceKm: 6.2,
            activeEnergyKcal: 410,
            avgHeartRate: 152,
            maxHeartRate: 174,
            route: []
        )
        let files = try WorkoutFilesSerializer().serialize(workouts: [workout])
        let jsonFile = try XCTUnwrap(files.first { $0.path.hasSuffix(".json") })
        let obj = try decode(jsonFile.data)
        XCTAssertEqual(obj["schema_version"] as? String, "1.0")
        XCTAssertEqual(obj["id"] as? String, "7f3a")
        XCTAssertEqual(obj["type"] as? String, "outdoor_run")
        XCTAssertEqual(obj["duration_minutes"] as? Int, 38)
        XCTAssertEqual(obj["distance_km"] as? Double, 6.2)
        XCTAssertEqual(obj["has_route"] as? Bool, false)
    }

    func testNoGPXForWorkoutWithoutRoute() throws {
        let workout = WorkoutDTO(
            id: "8b21",
            type: .yoga,
            startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
            endDate: SampleFixtures.iso("2026-05-14T07:30:00Z"),
            durationMinutes: 30,
            distanceKm: nil,
            activeEnergyKcal: nil,
            avgHeartRate: nil,
            maxHeartRate: nil,
            route: []
        )
        let files = try WorkoutFilesSerializer().serialize(workouts: [workout])
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].path.hasSuffix(".json"))
    }

    func testWorkoutJSONIncludesExactFieldsAndRecordedIntervals() throws {
        let start = SampleFixtures.iso("2026-05-14T07:00:00Z")
        let workout = WorkoutDTO(
            id: "ride", type: .outdoorCycling, startDate: start,
            endDate: start.addingTimeInterval(3_900), durationMinutes: 60,
            distanceKm: 30, activeEnergyKcal: 500, avgHeartRate: 140,
            maxHeartRate: 168, route: [], durationSeconds: 3_599.5,
            distanceMeters: 30_000, recordedIntervals: [
                WorkoutRecordedIntervalDTO(kind: .segment, startDate: start.addingTimeInterval(60), endDate: start.addingTimeInterval(180), durationSeconds: 120)
            ]
        )

        let file = try XCTUnwrap(WorkoutFilesSerializer().serialize(workouts: [workout]).first)
        let obj = try decode(file.data)

        XCTAssertEqual(obj["duration_seconds"] as? Double, 3_599.5)
        XCTAssertEqual(obj["distance_meters"] as? Double, 30_000)
        XCTAssertEqual(obj["average_speed_kph"] as? Double, 30.004167)
        XCTAssertNil(obj["average_pace_seconds_per_km"])
        XCTAssertEqual((obj["recorded_intervals"] as? [[String: Any]])?.count, 1)
    }
}
