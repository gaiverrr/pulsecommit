import Foundation
import HealthKit
import HealthCore

public final class BodyMassCategory: HealthCategory {
    public let id = "body_mass"
    public let displayName = "Body Mass"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: HKUnit.gramUnit(with: .kilo),
            categoryID: id
        )
        return samples
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        guard let latest = quantities.max(by: { $0.startDate < $1.startDate }) else {
            return SummaryFragment(metrics: [:], unit: "kg")
        }
        let rounded = (latest.value * 10).rounded() / 10
        return SummaryFragment(metrics: ["value": .double(rounded)], unit: "kg")
    }
}
