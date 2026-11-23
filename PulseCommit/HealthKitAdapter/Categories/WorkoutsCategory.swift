import Foundation
import HealthKit
import HealthCore

public final class WorkoutsCategory: HealthCategory {
    public let id = "workouts"
    public let displayName = "Workouts"

    private let store: any HealthStoreAuthorizing
    private let zoneConfiguration: HeartRateZoneConfiguration?

    public init(store: any HealthStoreAuthorizing, zoneConfiguration: HeartRateZoneConfiguration? = nil) {
        self.store = store
        self.zoneConfiguration = zoneConfiguration
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let workouts = try await fetchWorkouts(store: store, from: from, to: to)
        var dtos: [WorkoutSampleDTO] = []
        dtos.reserveCapacity(workouts.count)
        for workout in workouts {
            let route: [RoutePointDTO]
            do {
                route = try await fetchRoute(store: store, for: workout)
            } catch {
                route = []
            }
            var zones: WorkoutHeartRateZones?
            if let zoneConfiguration {
                let active = workoutActiveIntervals(start: workout.startDate, end: workout.endDate, events: workout.workoutEvents ?? [])
                let activeSeconds = active.reduce(0) { $0 + $1.duration }
                // Some imported workouts omit pause events. If their duration
                // cannot be reconciled, the pause locations are unknown.
                if abs(activeSeconds - workout.duration) <= 1,
                   let rates = try? await fetchWorkoutHeartRates(store: store, workout: workout) {
                    zones = HeartRateZoneEstimator.estimate(samples: rates, configuration: zoneConfiguration,
                        workout: DateInterval(start: workout.startDate, end: workout.endDate), activeIntervals: active)
                }
            }
            let workoutDTO = HKWorkoutMapping.map(workout, route: route, heartRateZones: zones)
            dtos.append(
                WorkoutSampleDTO(
                    categoryID: id,
                    sourceName: workout.sourceRevision.source.name,
                    sourceBundleID: workout.sourceRevision.source.bundleIdentifier,
                    workout: workoutDTO
                )
            )
        }
        return dtos
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let workouts = samples.compactMap { $0 as? WorkoutSampleDTO }
        return SummaryFragment(
            metrics: ["count": .int(workouts.count)],
            unit: "workouts"
        )
    }
}
