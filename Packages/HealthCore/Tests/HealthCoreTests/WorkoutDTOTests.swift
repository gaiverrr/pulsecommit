import XCTest
@testable import HealthCore

final class WorkoutDTOTests: XCTestCase {
    func test_exactFieldsDriveActivityAppropriatePaceAndSpeed() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let run = WorkoutDTO(
            id: "run", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(3_900), durationMinutes: 60,
            distanceKm: 10, activeEnergyKcal: nil, avgHeartRate: nil,
            maxHeartRate: nil, route: [], durationSeconds: 3_599.5,
            distanceMeters: 10_000
        )
        let cycling = WorkoutDTO(
            id: "ride", type: .outdoorCycling, startDate: start,
            endDate: start.addingTimeInterval(3_900), durationMinutes: 60,
            distanceKm: 30, activeEnergyKcal: nil, avgHeartRate: nil,
            maxHeartRate: nil, route: [], durationSeconds: 3_599.5,
            distanceMeters: 30_000
        )
        let strength = WorkoutDTO(
            id: "strength", type: .functionalStrengthTraining, startDate: start,
            endDate: start.addingTimeInterval(3_600), durationMinutes: 60,
            distanceKm: 10, activeEnergyKcal: nil, avgHeartRate: nil,
            maxHeartRate: nil, route: [], durationSeconds: 3_600,
            distanceMeters: 10_000
        )

        XCTAssertEqual(try XCTUnwrap(run.averagePaceSecondsPerKilometer), 359.95, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(cycling.averageSpeedKilometersPerHour), 30.004167, accuracy: 0.0001)
        XCTAssertNil(strength.averagePaceSecondsPerKilometer)
        XCTAssertNil(strength.averageSpeedKilometersPerHour)
    }

    func test_invalidExactMeasurementsDoNotProduceDerivedMetrics() {
        let start = Date(timeIntervalSince1970: 0)
        for (duration, distance) in [(0.0, 1_000.0), (-1.0, 1_000.0), (.infinity, 1_000.0), (60.0, 0.0), (60.0, .nan)] {
            let workout = WorkoutDTO(
                id: "invalid", type: .walking, startDate: start,
                endDate: start.addingTimeInterval(60), durationMinutes: 1,
                distanceKm: 1, activeEnergyKcal: nil, avgHeartRate: nil,
                maxHeartRate: nil, route: [], durationSeconds: duration,
                distanceMeters: distance
            )
            XCTAssertNil(workout.averagePaceSecondsPerKilometer)
        }
    }

    func test_legacyJSONDecodesWithoutExactFieldsOrRecordedIntervals() throws {
        let legacy = """
        {
          "id": "legacy",
          "type": "outdoor_run",
          "startDate": 0,
          "endDate": 600,
          "durationMinutes": 10,
          "distanceKm": 2,
          "route": []
        }
        """

        let decoded = try JSONDecoder().decode(WorkoutDTO.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.durationMinutes, 10)
        XCTAssertNil(decoded.durationSeconds)
        XCTAssertNil(decoded.distanceMeters)
        XCTAssertNil(decoded.recordedIntervals)
        XCTAssertNil(decoded.averagePaceSecondsPerKilometer)
    }

    func test_workoutDTO_roundTrip_includesRoute() throws {
        let workout = WorkoutDTO(
            id: "7f3a",
            type: .outdoorRun,
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_002_280),
            durationMinutes: 38,
            distanceKm: 6.2,
            activeEnergyKcal: 410,
            avgHeartRate: 152,
            maxHeartRate: 174,
            route: [
                RoutePointDTO(
                    time: Date(timeIntervalSince1970: 1_700_000_010),
                    latitude: 38.7,
                    longitude: -9.1,
                    elevationMeters: 12.0
                )
            ]
        )
        let data = try JSONEncoder().encode(workout)
        let decoded = try JSONDecoder().decode(WorkoutDTO.self, from: data)
        XCTAssertEqual(workout, decoded)
        XCTAssertTrue(decoded.hasRoute)
    }

    func test_workoutDTO_hasRoute_isFalseWhenRouteIsEmpty() {
        let workout = WorkoutDTO(
            id: "abc",
            type: .indoorCycling,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 1800),
            durationMinutes: 30,
            distanceKm: nil,
            activeEnergyKcal: 250,
            avgHeartRate: nil,
            maxHeartRate: nil,
            route: []
        )
        XCTAssertFalse(workout.hasRoute)
    }
}
