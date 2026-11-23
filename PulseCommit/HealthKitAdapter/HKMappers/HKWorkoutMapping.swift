import Foundation
import HealthKit
import HealthCore

public enum HKWorkoutMapping {
    public static func mapType(activity: HKWorkoutActivityType, isIndoor: Bool) -> WorkoutDTO.WorkoutType {
        switch activity {
        case .running:
            return isIndoor ? .indoorRun : .outdoorRun
        case .cycling:
            return isIndoor ? .indoorCycling : .outdoorCycling
        case .functionalStrengthTraining:
            return .functionalStrengthTraining
        case .traditionalStrengthTraining:
            return .traditionalStrengthTraining
        case .walking:
            return .walking
        case .hiking:
            return .hiking
        case .yoga:
            return .yoga
        case .swimming:
            return .swimming
        default:
            return .other
        }
    }

    public static func map(_ workout: HKWorkout, route: [RoutePointDTO] = [], heartRateZones: WorkoutHeartRateZones? = nil) -> WorkoutDTO {
        let isIndoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false
        let type = mapType(activity: workout.workoutActivityType, isIndoor: isIndoor)
        let elapsedSeconds = workout.endDate.timeIntervalSince(workout.startDate)
        let durationSeconds = positiveFinite(workout.duration).flatMap {
            $0 <= elapsedSeconds + 1 ? $0 : nil
        }
        let durationMinutes = durationSeconds.flatMap { safeRoundedInt($0 / 60) } ?? 0

        let distanceMeters = positiveFinite(workout.totalDistance?.doubleValue(for: .meter()))
        let distanceKm = distanceMeters.map { (($0 / 1_000) * 100).rounded() / 100 }

        let energyKcal = positiveFinite(workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()))?.rounded()

        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let heartRate = workout.statistics(for: heartRateType)
        let bpm = HKUnit.count().unitDivided(by: .minute())

        return WorkoutDTO(
            id: workout.uuid.uuidString,
            type: type,
            startDate: workout.startDate,
            endDate: workout.endDate,
            durationMinutes: durationMinutes,
            distanceKm: distanceKm,
            activeEnergyKcal: energyKcal,
            avgHeartRate: positiveFinite(heartRate?.averageQuantity()?.doubleValue(for: bpm)),
            maxHeartRate: positiveFinite(heartRate?.maximumQuantity()?.doubleValue(for: bpm)),
            route: route,
            heartRateZones: heartRateZones,
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
            recordedIntervals: mapRecordedIntervals(
                workout.workoutEvents,
                workoutStart: workout.startDate,
                workoutEnd: workout.endDate
            )
        )
    }

    private static func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func safeRoundedInt(_ value: Double) -> Int? {
        guard value.isFinite else { return nil }
        return Int(exactly: value.rounded())
    }

    static func mapRecordedIntervals(
        _ events: [HKWorkoutEvent]?,
        workoutStart: Date,
        workoutEnd: Date
    ) -> [WorkoutRecordedIntervalDTO]? {
        guard let events else { return nil }
        let intervals = events.enumerated().compactMap { index, event -> (Int, WorkoutRecordedIntervalDTO)? in
            let kind: WorkoutRecordedIntervalDTO.Kind
            switch event.type {
            case .lap: kind = .lap
            case .segment: kind = .segment
            default: return nil
            }

            let interval = event.dateInterval
            guard interval.start >= workoutStart,
                  interval.end <= workoutEnd,
                  interval.end > interval.start,
                  interval.duration.isFinite,
                  interval.duration > 0 else {
                return nil
            }
            return (
                index,
                WorkoutRecordedIntervalDTO(
                    kind: kind,
                    startDate: interval.start,
                    endDate: interval.end,
                    durationSeconds: interval.duration
                )
            )
        }
        .sorted { lhs, rhs in
            if lhs.1.startDate != rhs.1.startDate { return lhs.1.startDate < rhs.1.startDate }
            return lhs.0 < rhs.0
        }
        .map(\.1)

        return intervals.isEmpty ? nil : intervals
    }
}

public func fetchWorkouts(
    store: HealthStoreAuthorizing,
    from: Date,
    to: Date
) async throws -> [HKWorkout] {
    let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: HKObjectType.workoutType(),
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
        }
        store.execute(query)
    }
}
