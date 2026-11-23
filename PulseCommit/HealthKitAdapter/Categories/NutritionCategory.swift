import Foundation
import HealthKit
import HealthCore

public final class NutritionCategory: HealthCategory {
    public let id = "nutrition"
    public let displayName = "Nutrition"

    public struct Subtype: Sendable {
        public let subId: String
        public let metricKey: String
        public let identifier: HKQuantityTypeIdentifier
        public let unit: HKUnit
        public let unitLabel: String
    }

    public static let subtypes: [Subtype] = [
        .init(subId: "nutrition.energy", metricKey: "energy_kcal",
              identifier: .dietaryEnergyConsumed, unit: .kilocalorie(), unitLabel: "kcal"),
        .init(subId: "nutrition.protein", metricKey: "protein_g",
              identifier: .dietaryProtein, unit: .gram(), unitLabel: "g"),
        .init(subId: "nutrition.carbs", metricKey: "carbs_g",
              identifier: .dietaryCarbohydrates, unit: .gram(), unitLabel: "g"),
        .init(subId: "nutrition.fat", metricKey: "fat_g",
              identifier: .dietaryFatTotal, unit: .gram(), unitLabel: "g"),
        .init(subId: "nutrition.fiber", metricKey: "fiber_g",
              identifier: .dietaryFiber, unit: .gram(), unitLabel: "g"),
        .init(subId: "nutrition.sugar", metricKey: "sugar_g",
              identifier: .dietarySugar, unit: .gram(), unitLabel: "g"),
        .init(subId: "nutrition.water", metricKey: "water_ml",
              identifier: .dietaryWater, unit: .literUnit(with: .milli), unitLabel: "ml"),
        .init(subId: "nutrition.caffeine", metricKey: "caffeine_mg",
              identifier: .dietaryCaffeine, unit: .gramUnit(with: .milli), unitLabel: "mg")
    ]

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        try await withThrowingTaskGroup(of: [QuantitySampleDTO].self) { group in
            for sub in Self.subtypes {
                guard let type = HKQuantityType.quantityType(forIdentifier: sub.identifier) else { continue }
                group.addTask { [store] in
                    try await fetchQuantitySamples(
                        store: store,
                        type: type,
                        from: from,
                        to: to,
                        unit: sub.unit,
                        categoryID: sub.subId
                    )
                }
            }
            var all: [any SampleDTO] = []
            for try await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }
    }

    /// Cumulative metrics: dedup via HKStatisticsQuery. Nutrition is rarely written by
    /// multiple sources today, but logged third-party apps can double-count, so be
    /// consistent with other cumulative types.
    public var isCumulative: Bool { true }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        try await withThrowingTaskGroup(of: [QuantitySampleDTO].self) { group in
            for sub in Self.subtypes {
                guard let type = HKQuantityType.quantityType(forIdentifier: sub.identifier) else { continue }
                group.addTask { [store] in
                    try await fetchCumulativeTotal(
                        store: store,
                        type: type,
                        from: from,
                        to: to,
                        unit: sub.unit,
                        categoryID: sub.subId
                    )
                }
            }
            var all: [any SampleDTO] = []
            for try await batch in group {
                all.append(contentsOf: batch)
            }
            return all
        }
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        var metrics: [String: MetricValue] = [:]
        for sub in Self.subtypes {
            let total = quantities
                .filter { $0.categoryID == sub.subId }
                .reduce(0.0) { $0 + $1.value }
            let rounded = (total * 10).rounded() / 10
            metrics[sub.metricKey] = .double(rounded)
        }
        return SummaryFragment(metrics: metrics, unit: "mixed")
    }
}
