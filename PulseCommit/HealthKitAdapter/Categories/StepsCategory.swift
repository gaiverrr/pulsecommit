import Foundation
import HealthKit
import HealthCore

public final class StepsCategory: HealthCategory {
    public let id = "steps"
    public let displayName = "Steps"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.count(),
            categoryID: id
        )
        return samples
    }

    /// Cumulative metric: use HKStatisticsQuery so overlapping iPhone + Apple Watch samples
    /// aren't double-counted. The doubled fetch (here + `fetch` for raw samples) is
    /// intentional — see `fetchCumulativeTotal` in HKQuantitySampleMapping.swift.
    public var isCumulative: Bool { true }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        return try await fetchCumulativeTotal(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.count(),
            categoryID: id
        )
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        let total = quantities.reduce(0.0) { $0 + $1.value }
        return SummaryFragment(metrics: ["total": .int(Int(total.rounded()))], unit: "count")
    }
}
