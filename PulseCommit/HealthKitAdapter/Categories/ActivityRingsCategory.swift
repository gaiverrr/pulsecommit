import Foundation
import HealthKit
import HealthCore

public final class ActivityRingsCategory: HealthCategory {
    public let id = "activity_rings"
    public let displayName = "Activity Rings"

    public static let standSubId = "activity_rings.stand"
    public static let exerciseSubId = "activity_rings.exercise"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let standType = HKQuantityType.quantityType(forIdentifier: .appleStandTime)!
        let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!

        async let stand = fetchQuantitySamples(
            store: store,
            type: standType,
            from: from,
            to: to,
            unit: HKUnit.minute(),
            categoryID: Self.standSubId
        )
        async let exercise = fetchQuantitySamples(
            store: store,
            type: exerciseType,
            from: from,
            to: to,
            unit: HKUnit.minute(),
            categoryID: Self.exerciseSubId
        )

        let (s, e) = try await (stand, exercise)
        return s + e
    }

    /// Cumulative metrics: dedup via HKStatisticsQuery (Watch is primary writer but
    /// iPhone may contribute too — HKStatisticsQuery picks canonical overlaps).
    public var isCumulative: Bool { true }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        let standType = HKQuantityType.quantityType(forIdentifier: .appleStandTime)!
        let exerciseType = HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!

        async let stand = fetchCumulativeTotal(
            store: store,
            type: standType,
            from: from,
            to: to,
            unit: HKUnit.minute(),
            categoryID: Self.standSubId
        )
        async let exercise = fetchCumulativeTotal(
            store: store,
            type: exerciseType,
            from: from,
            to: to,
            unit: HKUnit.minute(),
            categoryID: Self.exerciseSubId
        )

        let (s, e) = try await (stand, exercise)
        return s + e
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let quantities = samples.compactMap { $0 as? QuantitySampleDTO }
        let standMinutes = quantities
            .filter { $0.categoryID == Self.standSubId }
            .reduce(0.0) { $0 + $1.value }
        let exerciseMinutes = quantities
            .filter { $0.categoryID == Self.exerciseSubId }
            .reduce(0.0) { $0 + $1.value }

        let standHours = (standMinutes / 60.0)
        let standHoursRounded = (standHours * 10).rounded() / 10

        return SummaryFragment(
            metrics: [
                "stand_hours": .double(standHoursRounded),
                "exercise_minutes": .int(Int(exerciseMinutes.rounded()))
            ],
            unit: "mixed"
        )
    }
}
