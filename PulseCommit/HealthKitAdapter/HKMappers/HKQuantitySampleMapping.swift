import Foundation
import HealthKit
import HealthCore

public enum HKQuantitySampleMapping {
    public static func map(_ sample: HKQuantitySample, categoryID: String, unit: HKUnit) -> QuantitySampleDTO {
        QuantitySampleDTO(
            categoryID: categoryID,
            startDate: sample.startDate,
            endDate: sample.endDate,
            value: sample.quantity.doubleValue(for: unit),
            unit: unit.unitString,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleID: sample.sourceRevision.source.bundleIdentifier
        )
    }
}

/// Fetches HealthKit's cross-source deduplicated cumulative total for a quantity type
/// (e.g. stepCount, activeEnergyBurned). When both iPhone and Apple Watch record the
/// same metric, HKStatisticsQuery picks the canonical sample per overlap — preventing
/// the 2× double-count that a naive `HKSampleQuery → .reduce(+)` produces.
///
/// Returns a single `QuantitySampleDTO` carrying the deduplicated total, spanning the
/// requested range. The DTO has no real per-sample provenance (HealthKit hides this),
/// so `sourceName` is set to the synthetic "HealthKit (deduplicated)" marker.
/// Returns an empty array when there is no data in range.
public func fetchCumulativeTotal(
    store: HealthStoreAuthorizing,
    type: HKQuantityType,
    from: Date,
    to: Date,
    unit: HKUnit,
    categoryID: String
) async throws -> [QuantitySampleDTO] {
    let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
    guard let total = try await store.cumulativeSum(of: type, predicate: predicate, unit: unit) else {
        return []
    }
    return [
        QuantitySampleDTO(
            categoryID: categoryID,
            startDate: from,
            endDate: to,
            value: total,
            unit: unit.unitString,
            sourceName: "HealthKit (deduplicated)",
            sourceBundleID: "com.apple.health"
        )
    ]
}

public func fetchQuantitySamples(
    store: HealthStoreAuthorizing,
    type: HKQuantityType,
    from: Date,
    to: Date,
    unit: HKUnit,
    categoryID: String
) async throws -> [QuantitySampleDTO] {
    let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { continuation in
        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, samples, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            let quantitySamples = (samples as? [HKQuantitySample]) ?? []
            let dtos = quantitySamples.map { HKQuantitySampleMapping.map($0, categoryID: categoryID, unit: unit) }
            continuation.resume(returning: dtos)
        }
        store.execute(query)
    }
}
