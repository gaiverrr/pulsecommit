import XCTest
@testable import HealthCore

final class SamplesJSONSerializerTests: XCTestCase {
    private func decode(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testProducesOneFilePerCategoryAtExpectedPath() throws {
        let steps: [any SampleDTO] = [
            SampleFixtures.quantity(categoryID: "steps", start: "2026-05-14T08:00:00Z", value: 1200),
            SampleFixtures.quantity(categoryID: "steps", start: "2026-05-14T12:00:00Z", value: 800)
        ]
        let rhr: [any SampleDTO] = [
            SampleFixtures.quantity(categoryID: "resting_heart_rate", start: "2026-05-14T07:00:00Z", value: 58, unit: "count/min")
        ]
        let files = try SamplesJSONSerializer().serialize(samplesByCategory: [
            "steps": steps,
            "resting_heart_rate": rhr
        ])
        let paths = files.map(\.path).sorted()
        XCTAssertEqual(paths, ["samples/resting_heart_rate.json", "samples/steps.json"])
    }

    func testFilePayloadContainsSchemaVersionAndCategory() throws {
        let steps: [any SampleDTO] = [
            SampleFixtures.quantity(categoryID: "steps", start: "2026-05-14T08:00:00Z", value: 1200)
        ]
        let files = try SamplesJSONSerializer().serialize(samplesByCategory: ["steps": steps])
        let file = try XCTUnwrap(files.first)
        let obj = try decode(file.data)
        XCTAssertEqual(obj["schema_version"] as? String, "1.0")
        XCTAssertEqual(obj["category"] as? String, "steps")
        let samples = try XCTUnwrap(obj["samples"] as? [[String: Any]])
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0]["categoryId"] as? String, "steps")
        XCTAssertEqual(samples[0]["value"] as? Double, 1200)
        XCTAssertEqual(samples[0]["unit"] as? String, "count")
    }

    func testEmptyCategoryStillEmitsFile() throws {
        let files = try SamplesJSONSerializer().serialize(samplesByCategory: ["steps": []])
        XCTAssertEqual(files.count, 1)
        let obj = try decode(files[0].data)
        XCTAssertEqual(obj["category"] as? String, "steps")
        XCTAssertEqual((obj["samples"] as? [Any])?.count, 0)
    }


    func testWorkoutSampleCarriesExactFieldsAndRecordedIntervals() throws {
        let start = SampleFixtures.iso("2026-05-14T07:00:00Z")
        let workout = WorkoutDTO(
            id: "run", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(650), durationMinutes: 10,
            distanceKm: 2, activeEnergyKcal: 180, avgHeartRate: 150,
            maxHeartRate: 170, route: [], durationSeconds: 600.25,
            distanceMeters: 2_000, recordedIntervals: [
                WorkoutRecordedIntervalDTO(kind: .lap, startDate: start, endDate: start.addingTimeInterval(300), durationSeconds: 300)
            ]
        )
        let sample = WorkoutSampleDTO(categoryID: "workouts", sourceName: "Watch", sourceBundleID: "com.apple.health", workout: workout)

        let file = try XCTUnwrap(SamplesJSONSerializer().serialize(samplesByCategory: ["workouts": [sample]]).first)
        let obj = try decode(file.data)
        let samples = try XCTUnwrap(obj["samples"] as? [[String: Any]])
        let encodedWorkout = try XCTUnwrap(samples.first?["workout"] as? [String: Any])

        XCTAssertEqual(encodedWorkout["durationSeconds"] as? Double, 600.25)
        XCTAssertEqual(encodedWorkout["distanceMeters"] as? Double, 2_000)
        let intervals = try XCTUnwrap(encodedWorkout["recordedIntervals"] as? [[String: Any]])
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0]["duration_seconds"] as? Double, 300)
    }
}
