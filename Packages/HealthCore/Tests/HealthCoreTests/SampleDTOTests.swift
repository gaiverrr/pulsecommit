import XCTest
@testable import HealthCore

final class SampleDTOTests: XCTestCase {
    func test_quantitySampleDTO_encodesAndDecodesRoundTrip() throws {
        let original = QuantitySampleDTO(
            categoryID: "steps",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_060),
            value: 42,
            unit: "count",
            sourceName: "iPhone",
            sourceBundleID: "com.apple.health"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(QuantitySampleDTO.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_categorySampleDTO_encodesAndDecodesRoundTrip() throws {
        let original = CategorySampleDTO(
            categoryID: "sleep",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_030_000),
            value: 3,
            metadata: ["label": "core"],
            sourceName: "Apple Watch",
            sourceBundleID: "com.apple.health"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CategorySampleDTO.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_quantitySampleDTO_decoding_failsOnMissingRequiredField() {
        let json = #"""
        {
          "categoryId": "steps",
          "startDate": 0,
          "endDate": 1,
          "value": 10,
          "sourceName": "iPhone",
          "sourceBundleId": "com.apple.health"
        }
        """#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(QuantitySampleDTO.self, from: json))
    }

    func test_workoutSampleDTO_encodesAndDecodesRoundTrip() throws {
        let workout = WorkoutDTO(
            id: "WK-1",
            type: .outdoorRun,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
            durationMinutes: 60,
            distanceKm: 10.5,
            activeEnergyKcal: 700,
            avgHeartRate: 152,
            maxHeartRate: 178,
            route: [
                RoutePointDTO(time: Date(timeIntervalSince1970: 1_700_000_000), latitude: 1.23, longitude: 4.56, elevationMeters: 12.0)
            ]
        )
        let original = WorkoutSampleDTO(
            categoryID: "workouts",
            sourceName: "Apple Watch",
            sourceBundleID: "com.apple.health",
            workout: workout
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutSampleDTO.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.startDate, workout.startDate)
        XCTAssertEqual(decoded.endDate, workout.endDate)
        XCTAssertTrue(decoded.workout.hasRoute)
    }

    func test_categorySampleDTO_decoding_failsOnWrongValueType() {
        let json = #"""
        {
          "categoryId": "sleep",
          "startDate": 0,
          "endDate": 1,
          "value": "three",
          "metadata": {},
          "sourceName": "Apple Watch",
          "sourceBundleId": "com.apple.health"
        }
        """#.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(CategorySampleDTO.self, from: json))
    }
}
