import Foundation
import HealthKit
import HealthCore

public final class DistanceWalkingRunningCategory: HealthCategory {
    public let id = "distance_walking_running"
    public let displayName = "Distance"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.meterUnit(with: .kilo),
            categoryID: id
        )
        return samples
    }

    /// Cumulative metric: dedup via HKStatisticsQuery (Watch + iPhone overlap).
    public var isCumulative: Bool { true }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
        return try await fetchCumulativeTotal(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.meterUnit(with: .kilo),
            categoryID: id
        )
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        let total = quantities.reduce(0.0) { $0 + $1.value }
        let rounded = (total * 100).rounded() / 100
        return SummaryFragment(metrics: ["total": .double(rounded)], unit: "km")
    }
}
