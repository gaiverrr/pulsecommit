import Foundation
import HealthKit
import HealthCore

public final class RestingHeartRateCategory: HealthCategory {
    public let id = "resting_heart_rate"
    public let displayName = "Resting Heart Rate"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!
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
        guard let latest = quantities.max(by: { $0.startDate < $1.startDate }) else {
            return SummaryFragment(metrics: [:], unit: "bpm")
        }
        return SummaryFragment(metrics: ["value": .int(Int(latest.value.rounded()))], unit: "bpm")
    }
}
