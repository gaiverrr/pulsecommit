import Foundation
import HealthKit
import HealthCore

public final class HRVCategory: HealthCategory {
    public let id = "hrv_sdnn"
    public let displayName = "HRV"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.secondUnit(with: .milli),
            categoryID: id
        )
        return samples
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        guard !quantities.isEmpty else {
            return SummaryFragment(metrics: [:], unit: "ms")
        }
        let sum = quantities.reduce(0.0) { $0 + $1.value }
        let avg = sum / Double(quantities.count)
        return SummaryFragment(metrics: [
            "avg": .int(Int(avg.rounded())),
            "sample_count": .int(quantities.count)
        ], unit: "ms")
    }
}
