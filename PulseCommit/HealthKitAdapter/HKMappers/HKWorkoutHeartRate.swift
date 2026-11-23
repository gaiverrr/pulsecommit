import Foundation
import HealthKit
import HealthCore

func fetchWorkoutHeartRates(store: any HealthStoreAuthorizing, workout: HKWorkout) async throws -> [QuantitySampleDTO] {
    let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    let predicate = HKQuery.predicateForObjects(from: workout)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
            if let error { continuation.resume(throwing: error); return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let result = (samples as? [HKQuantitySample] ?? []).map {
                HKQuantitySampleMapping.map($0, categoryID: "heart_rate", unit: unit)
            }
            continuation.resume(returning: result)
        }
        store.execute(query)
    }
}

func workoutActiveIntervals(start: Date, end: Date, events: [HKWorkoutEvent]) -> [DateInterval] {
    guard end > start else { return [] }
    var result: [DateInterval] = []
    var cursor = start
    var paused = false
    var motionPaused = false
    let ordered = events.enumerated().sorted {
        if $0.element.dateInterval.start == $1.element.dateInterval.start { return $0.offset < $1.offset }
        return $0.element.dateInterval.start < $1.element.dateInterval.start
    }
    for (_, event) in ordered {
        let time = event.dateInterval.start
        guard time >= start, time <= end else { continue }
        if !paused && !motionPaused && time > cursor { result.append(DateInterval(start: cursor, end: time)) }
        switch event.type {
        case .pause: paused = true
        case .resume: paused = false
        case .motionPaused: motionPaused = true
        case .motionResumed: motionPaused = false
        default: break
        }
        cursor = time
    }
    if !paused && !motionPaused && end > cursor { result.append(DateInterval(start: cursor, end: end)) }
    return result
}
