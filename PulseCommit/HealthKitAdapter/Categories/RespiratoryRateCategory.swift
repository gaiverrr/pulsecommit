import Foundation
import HealthKit
import HealthCore

public final class RespiratoryRateCategory: HealthCategory {
    public let id = "respiratory_rate"
    public let displayName = "Sleep Respiratory Rate"
    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) { self.store = store }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        try await fetchQuantitySamples(
            store: store, type: HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!,
            from: from, to: to, unit: HKUnit.count().unitDivided(by: .minute()), categoryID: id
        )
    }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        let sessions = try await SleepCategory(store: store).fetchSummarySamples(from: from, to: to)
            .compactMap { $0 as? SleepSessionSample }
        guard let earliest = sessions.map(\.sleepStart).min() else { return [] }
        let rates = try await fetch(from: earliest, to: to).compactMap { $0 as? QuantitySampleDTO }
        return Self.sleepSamples(rates, sessions: sessions)
    }

    static func sleepSamples(_ rates: [QuantitySampleDTO], sessions: [SleepSessionSample]) -> [QuantitySampleDTO] {
        rates.compactMap { rate in
            guard rate.value.isFinite, rate.value > 0,
                  let session = sessions.first(where: { session in
                      session.asleepSamples.contains { rate.startDate >= $0.startDate && rate.startDate < $0.endDate }
                  }) else { return nil }
            return QuantitySampleDTO(
                categoryID: rate.categoryID, startDate: session.sleepEnd, endDate: session.sleepEnd,
                value: rate.value, unit: rate.unit, sourceName: rate.sourceName, sourceBundleID: rate.sourceBundleID
            )
        }
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let rates = samples.compactMap { $0 as? QuantitySampleDTO }.filter { $0.value.isFinite && $0.value > 0 }
        guard !rates.isEmpty else { return SummaryFragment(unit: "breaths/min") }
        let average = rates.reduce(0.0) { $0 + $1.value } / Double(rates.count)
        return SummaryFragment(metrics: [
            "sleep_avg": .double((average * 10).rounded() / 10),
            "sample_count": .int(rates.count)
        ], unit: "breaths/min")
    }
}
