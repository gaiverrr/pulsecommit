import XCTest
@testable import HealthCore

final class SummaryJSONSerializerTests: XCTestCase {
    private func makeSnapshot() -> DailySnapshot {
        let date = SampleFixtures.iso("2026-05-14T00:00:00Z")
        let generated = SampleFixtures.iso("2026-05-14T22:30:12Z")
        var snap = DailySnapshot(
            date: date,
            timezone: "Europe/Lisbon",
            generatedAt: generated,
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snap.unavailableCategories = []
        snap.summaries = [
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count"),
            "resting_heart_rate": SummaryFragment(metrics: ["value": .int(58)], unit: "bpm")
        ]
        snap.workouts = [
            WorkoutDTO(
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
                    RoutePointDTO(time: SampleFixtures.iso("2026-05-14T07:00:00Z"), latitude: 38.7, longitude: -9.1, elevationMeters: 12)
                ]
            ),
            WorkoutDTO(
                id: "abc1",
                type: .functionalStrengthTraining,
                startDate: SampleFixtures.iso("2026-05-14T18:00:00Z"),
                endDate: SampleFixtures.iso("2026-05-14T18:45:00Z"),
                durationMinutes: 45,
                distanceKm: nil,
                activeEnergyKcal: 280,
                avgHeartRate: nil,
                maxHeartRate: nil,
                route: []
            )
        ]
        snap.stateOfMind = [
            StateOfMindEntryDTO(
                time: SampleFixtures.iso("2026-05-14T08:15:00Z"),
                valence: 0.4,
                labels: ["calm", "focused"]
            )
        ]
        return snap
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTopLevelKeys() throws {
        let data = try SummaryJSONSerializer().serialize(makeSnapshot())
        let obj = try decode(data)
        XCTAssertEqual(obj["schema_version"] as? String, "1.0")
        XCTAssertEqual(obj["date"] as? String, "2026-05-14")
        XCTAssertEqual(obj["timezone"] as? String, "Europe/Lisbon")
        XCTAssertEqual(obj["generated_at"] as? String, "2026-05-14T22:30:12Z")
        XCTAssertEqual(obj["device"] as? String, "iPhone 15 Pro")
        XCTAssertEqual(obj["app_version"] as? String, "1.0.0")
        XCTAssertNotNil(obj["unavailable_categories"] as? [String])
        XCTAssertNotNil(obj["metrics"] as? [String: Any])
        XCTAssertNotNil(obj["workouts"] as? [Any])
        XCTAssertNotNil(obj["state_of_mind"] as? [Any])
    }

    func testMetricsMapShape() throws {
        let data = try SummaryJSONSerializer().serialize(makeSnapshot())
        let obj = try decode(data)
        let metrics = try XCTUnwrap(obj["metrics"] as? [String: Any])
        let steps = try XCTUnwrap(metrics["steps"] as? [String: Any])
        XCTAssertEqual(steps["total"] as? Int, 12483)
        XCTAssertEqual(steps["unit"] as? String, "count")

        let rhr = try XCTUnwrap(metrics["resting_heart_rate"] as? [String: Any])
        XCTAssertEqual(rhr["value"] as? Int, 58)
        XCTAssertEqual(rhr["unit"] as? String, "bpm")
    }

    func testWorkoutHasRouteTruthiness() throws {
        let data = try SummaryJSONSerializer().serialize(makeSnapshot())
        let obj = try decode(data)
        let workouts = try XCTUnwrap(obj["workouts"] as? [[String: Any]])
        XCTAssertEqual(workouts.count, 2)
        let routed = try XCTUnwrap(workouts.first { ($0["id"] as? String) == "7f3a" })
        XCTAssertEqual(routed["has_route"] as? Bool, true)
        XCTAssertEqual(routed["type"] as? String, "outdoor_run")
        XCTAssertEqual(routed["duration_minutes"] as? Int, 38)
        XCTAssertEqual(routed["distance_km"] as? Double, 6.2)
        XCTAssertEqual(routed["avg_hr"] as? Int, 152)

        let strength = try XCTUnwrap(workouts.first { ($0["id"] as? String) == "abc1" })
        XCTAssertEqual(strength["has_route"] as? Bool, false)
        XCTAssertNil(strength["distance_km"])
        XCTAssertNil(strength["avg_hr"])
    }

    func testWorkoutCarriesExactTimingDerivedPaceAndAllRecordedIntervals() throws {
        var snapshot = makeSnapshot()
        let start = SampleFixtures.iso("2026-05-14T07:00:00Z")
        snapshot.workouts = [WorkoutDTO(
            id: "precise", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(2_600), durationMinutes: 40,
            distanceKm: 8, activeEnergyKcal: 612, avgHeartRate: 152,
            maxHeartRate: 176, route: [], durationSeconds: 2_399.5,
            distanceMeters: 8_001.25, recordedIntervals: [
                WorkoutRecordedIntervalDTO(kind: .lap, startDate: start, endDate: start.addingTimeInterval(300), durationSeconds: 300),
                WorkoutRecordedIntervalDTO(kind: .segment, startDate: start.addingTimeInterval(240), endDate: start.addingTimeInterval(600), durationSeconds: 360)
            ]
        )]

        let obj = try decode(SummaryJSONSerializer().serialize(snapshot))
        let workouts = try XCTUnwrap(obj["workouts"] as? [[String: Any]])
        let workout = try XCTUnwrap(workouts.first)
        XCTAssertEqual(workout["start_date"] as? String, "2026-05-14T07:00:00Z")
        XCTAssertEqual(workout["end_date"] as? String, "2026-05-14T07:43:20Z")
        XCTAssertEqual(workout["duration_seconds"] as? Double, 2_399.5)
        XCTAssertEqual(workout["distance_meters"] as? Double, 8_001.25)
        XCTAssertEqual(workout["average_pace_seconds_per_km"] as? Double, 299.890642)
        XCTAssertNil(workout["average_speed_kph"])
        let intervals = try XCTUnwrap(workout["recorded_intervals"] as? [[String: Any]])
        XCTAssertEqual(intervals.count, 2)
        XCTAssertEqual(intervals[0]["kind"] as? String, "lap")
        XCTAssertEqual(intervals[1]["kind"] as? String, "segment")
    }

    func testStateOfMindShape() throws {
        let data = try SummaryJSONSerializer().serialize(makeSnapshot())
        let obj = try decode(data)
        let som = try XCTUnwrap(obj["state_of_mind"] as? [[String: Any]])
        XCTAssertEqual(som.count, 1)
        XCTAssertEqual(som[0]["time"] as? String, "2026-05-14T08:15:00Z")
        XCTAssertEqual(som[0]["valence"] as? Double, 0.4)
        XCTAssertEqual(som[0]["labels"] as? [String], ["calm", "focused"])
    }

    func testOutputIsSortedAndPretty() throws {
        let data = try SummaryJSONSerializer().serialize(makeSnapshot())
        let str = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(str.contains("\n"))
        let schemaIdx = try XCTUnwrap(str.range(of: "\"schema_version\""))
        let workoutsIdx = try XCTUnwrap(str.range(of: "\"workouts\""))
        XCTAssertLessThan(schemaIdx.lowerBound, workoutsIdx.lowerBound)
    }
    func testLatestSampleTimestampIsOptionalAndIndependentOfGeneration() throws {
        var snap = makeSnapshot()
        let legacy = try decode(SummaryJSONSerializer().serialize(snap))
        XCTAssertNil(legacy["latest_sample_at"])
        snap.latestSampleAt = SampleFixtures.iso("2026-05-14T20:00:00Z")
        let updated = try decode(SummaryJSONSerializer().serialize(snap))
        XCTAssertEqual(updated["latest_sample_at"] as? String, "2026-05-14T20:00:00Z")
        XCTAssertEqual(updated["generated_at"] as? String, "2026-05-14T22:30:12Z")
    }

    func testLegacyDailySnapshotDecodesWithoutLatestSampleTimestamp() throws {
        let original = makeSnapshot()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DailySnapshot.self, from: data)
        XCTAssertNil(decoded.latestSampleAt)
        XCTAssertEqual(decoded, original)
    }

}
