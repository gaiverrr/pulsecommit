import Foundation
import HealthKit
import HealthCore

public final class VO2MaxCategory: HealthCategory {
    public let id = "vo2_max"
    public let displayName = "VO₂ Max"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    private var unit: HKUnit {
        HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKQuantityType.quantityType(forIdentifier: .vo2Max)!
        let samples = try await fetchQuantitySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            unit: unit,
            categoryID: id
        )
        return samples
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        guard let latest = quantities.max(by: { $0.startDate < $1.startDate }) else {
            return SummaryFragment(metrics: [:], unit: "ml/kg·min")
        }
        let rounded = (latest.value * 10).rounded() / 10
        return SummaryFragment(metrics: ["value": .double(rounded)], unit: "ml/kg·min")
    }
}
