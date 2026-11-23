import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class HKWorkoutMappingTests: XCTestCase {
    func test_map_preservesExactMeasurementsAndOnlyValidRecordedIntervals() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_900)
        let events = [
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: start.addingTimeInterval(900), duration: 300), metadata: nil),
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start.addingTimeInterval(60), duration: 600), metadata: nil),
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start.addingTimeInterval(700), duration: 0), metadata: nil),
            HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: start.addingTimeInterval(800), duration: 0), metadata: nil),
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: start.addingTimeInterval(1_000), duration: 300), metadata: nil)
        ]
        let workout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            workoutEvents: events,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: 612.4),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: 8_001.25),
            metadata: nil
        )

        let dto = HKWorkoutMapping.map(workout)

        XCTAssertEqual(try XCTUnwrap(dto.durationSeconds), workout.duration, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(dto.distanceMeters), 8_001.25, accuracy: 0.001)
        XCTAssertEqual(dto.activeEnergyKcal, 612)
        XCTAssertEqual(dto.recordedIntervals, [
            WorkoutRecordedIntervalDTO(kind: .lap, startDate: start.addingTimeInterval(60), endDate: start.addingTimeInterval(660), durationSeconds: 600),
            WorkoutRecordedIntervalDTO(kind: .segment, startDate: start.addingTimeInterval(900), endDate: start.addingTimeInterval(1_200), durationSeconds: 300),
            WorkoutRecordedIntervalDTO(kind: .segment, startDate: start.addingTimeInterval(1_000), endDate: start.addingTimeInterval(1_300), durationSeconds: 300)
        ])
    }

    func test_mapRecordedIntervals_rejectsOutOfRangeIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)
        let intervals = HKWorkoutMapping.mapRecordedIntervals([
            HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: start.addingTimeInterval(-1), duration: 30), metadata: nil),
            HKWorkoutEvent(type: .segment, dateInterval: DateInterval(start: end.addingTimeInterval(-10), duration: 20), metadata: nil)
        ], workoutStart: start, workoutEnd: end)

        XCTAssertNil(intervals)
    }

    func test_map_omitsNonFiniteOrNonPositiveMeasurements() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = HKWorkout(
            activityType: .cycling,
            start: start,
            end: start.addingTimeInterval(60),
            duration: 60,
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: -.infinity),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: -1),
            metadata: nil
        )

        let dto = HKWorkoutMapping.map(workout)

        XCTAssertEqual(dto.durationSeconds, 60)
        XCTAssertNil(dto.distanceMeters)
        XCTAssertNil(dto.distanceKm)
        XCTAssertNil(dto.activeEnergyKcal)
    }

    func test_map_outdoorRun_producesExpectedDTO() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3600)
        let distance = HKQuantity(unit: .meterUnit(with: .kilo), doubleValue: 10.0)
        let energy = HKQuantity(unit: .kilocalorie(), doubleValue: 720)
        let workout = HKWorkout(
            activityType: .running,
            start: start,
            end: end,
            duration: 3600,
            totalEnergyBurned: energy,
            totalDistance: distance,
            metadata: [HKMetadataKeyIndoorWorkout: false]
        )

        let dto = HKWorkoutMapping.map(workout)

        XCTAssertEqual(dto.type, .outdoorRun)
        XCTAssertEqual(dto.startDate, start)
        XCTAssertEqual(dto.endDate, end)
        XCTAssertEqual(dto.durationMinutes, 60)
        XCTAssertEqual(dto.distanceKm, 10.0)
        XCTAssertEqual(dto.activeEnergyKcal, 720)
        XCTAssertFalse(dto.hasRoute)
        XCTAssertNil(dto.avgHeartRate)
        XCTAssertNil(dto.maxHeartRate)
    }

    func test_map_indoorRun_classifiedFromMetadata() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let workout = HKWorkout(
            activityType: .running,
            start: start,
            end: start.addingTimeInterval(1800),
            duration: 1800,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: [HKMetadataKeyIndoorWorkout: true]
        )

        let dto = HKWorkoutMapping.map(workout)

        XCTAssertEqual(dto.type, .indoorRun)
        XCTAssertNil(dto.distanceKm)
        XCTAssertNil(dto.activeEnergyKcal)
    }

    func test_mapType_unknownActivityFallsBackToOther() {
        XCTAssertEqual(HKWorkoutMapping.mapType(activity: .americanFootball, isIndoor: false), .other)
    }
}
