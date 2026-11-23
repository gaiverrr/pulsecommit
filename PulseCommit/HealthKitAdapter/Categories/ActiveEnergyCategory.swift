import Foundation
import HealthKit
import HealthCore

public final class ActiveEnergyCategory: HealthCategory {
    public let id = "active_energy"
    public let displayName = "Active Energy"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.kilocalorie(),
            categoryID: id
        )
        return samples
    }

    /// Cumulative metric: dedup via HKStatisticsQuery (Watch + iPhone overlap).
    public var isCumulative: Bool { true }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        return try await fetchCumulativeTotal(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.kilocalorie(),
            categoryID: id
        )
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        let total = quantities.reduce(0.0) { $0 + $1.value }
        return SummaryFragment(metrics: ["total": .int(Int(total.rounded()))], unit: "kcal")
    }
}
