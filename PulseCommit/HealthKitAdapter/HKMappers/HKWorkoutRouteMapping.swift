import Foundation
import HealthKit
import CoreLocation
import HealthCore

public enum HKWorkoutRouteMapping {
    public static func map(_ locations: [CLLocation]) -> [RoutePointDTO] {
        locations.map { location in
            let elevation: Double? = location.verticalAccuracy >= 0 ? location.altitude : nil
            return RoutePointDTO(
                time: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                elevationMeters: elevation
            )
        }
    }
}

public func fetchRoute(
    store: HealthStoreAuthorizing,
    for workout: HKWorkout
) async throws -> [RoutePointDTO] {
    let predicate = HKQuery.predicateForObjects(from: workout)
    let routeType = HKSeriesType.workoutRoute()

    let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: routeType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            continuation.resume(returning: (samples as? [HKWorkoutRoute]) ?? [])
        }
        store.execute(query)
    }

    var points: [RoutePointDTO] = []
    for route in routes {
        let locations = try await fetchLocations(store: store, for: route)
        points.append(contentsOf: HKWorkoutRouteMapping.map(locations))
    }
    return points
}

private final class RouteCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [CLLocation] = []
    private var resumed = false

    func handle(
        locations: [CLLocation]?,
        done: Bool,
        error: Error?,
        continuation: CheckedContinuation<[CLLocation], Error>
    ) {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return }
        if let error {
            resumed = true
            continuation.resume(throwing: error)
            return
        }
        if let locations {
            collected.append(contentsOf: locations)
        }
        if done {
            resumed = true
            continuation.resume(returning: collected)
        }
    }
}

private func fetchLocations(
    store: HealthStoreAuthorizing,
    for route: HKWorkoutRoute
) async throws -> [CLLocation] {
    try await withCheckedThrowingContinuation { continuation in
        let collector = RouteCollector()
        let query = HKWorkoutRouteQuery(route: route) { _, locationsOrNil, done, errorOrNil in
            collector.handle(
                locations: locationsOrNil,
                done: done,
                error: errorOrNil,
                continuation: continuation
            )
        }
        store.execute(query)
    }
}
