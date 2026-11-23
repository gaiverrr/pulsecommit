import Foundation
import HealthKit
import HealthCore

public final class HeartRateCategory: HealthCategory {
    public let id = "heart_rate"
    public let displayName = "Heart Rate"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.count().unitDivided(by: .minute()),
            categoryID: id
        )
        return samples
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        guard !quantities.isEmpty else {
            return SummaryFragment(metrics: [:], unit: "count/min")
        }
        let sum = quantities.reduce(0.0) { $0 + $1.value }
        let avg = sum / Double(quantities.count)
        let max = quantities.map(\.value).max() ?? 0
        return SummaryFragment(
            metrics: [
                "avg": .int(Int(avg.rounded())),
                "max": .int(Int(max.rounded()))
            ],
            unit: "count/min"
        )
    }
}
