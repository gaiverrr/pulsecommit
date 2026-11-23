import Foundation
import HealthKit
import HealthCore

public final class WristTemperatureCategory: HealthCategory {
    public let id = "wrist_temperature"
    public let displayName = "Wrist Temperature"
    private let store: any HealthStoreAuthorizing
    private let timezone: TimeZone

    public init(store: any HealthStoreAuthorizing, timezone: TimeZone = .current) {
        self.store = store
        self.timezone = timezone
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        try await fetchQuantitySamples(
            store: store, type: HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!,
            from: from, to: to, unit: .degreeCelsius(), categoryID: id
        )
    }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        // One extra day includes the start of overnight records ending on the
        // first baseline day. Baseline membership is based on local end dates.
        let lookback = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: from))!
        let samples = try await fetch(from: lookback, to: to).compactMap { $0 as? QuantitySampleDTO }
        return WristTemperatureBaseline.summaries(samples: samples, from: from, to: to, timezone: timezone).map {
            WristTemperatureSummarySample(startDate: $0.date, fragment: $0.fragment)
        }
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        samples.compactMap { $0 as? WristTemperatureSummarySample }.max { $0.startDate < $1.startDate }?.fragment
            ?? SummaryFragment(unit: "degC")
    }
}

private struct WristTemperatureSummarySample: SampleDTO {
    let startDate: Date
    let fragment: SummaryFragment
    var endDate: Date { startDate }
    var categoryID: String { "wrist_temperature" }
    var sourceName: String { "PulseCommit baseline" }
    var sourceBundleID: String { "app.pulsecommit" }
}
