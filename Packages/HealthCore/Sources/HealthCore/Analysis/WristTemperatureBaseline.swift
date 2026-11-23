import Foundation

public struct WristTemperatureDay: Sendable {
    public let date: Date
    public let fragment: SummaryFragment
}

public enum WristTemperatureBaseline {
    public static let windowDays = 28
    public static let minimumNights = 5

    public static func summaries(
        samples: [QuantitySampleDTO], from: Date, to: Date, timezone: TimeZone
    ) -> [WristTemperatureDay] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let valid = samples.filter { $0.value.isFinite && $0.endDate >= $0.startDate && $0.endDate < to }
        let days = Dictionary(grouping: valid) { calendar.startOfDay(for: $0.endDate) }
        return days.keys.sorted().compactMap { day in
            let current = days[day]!
            guard let latest = current.max(by: {
                if $0.endDate != $1.endDate { return $0.endDate < $1.endDate }
                return source($0) < source($1)
            }), latest.endDate >= from else { return nil }
            let currentValues = current.filter { source($0) == source(latest) }
            let average = mean(currentValues)
            let historyStart = calendar.date(byAdding: .day, value: -windowDays, to: day)!
            let previousNights = days.keys.filter { $0 >= historyStart && $0 < day }.sorted().compactMap { date -> Double? in
                let sameSource = days[date]!.filter { source($0) == source(latest) }
                return sameSource.isEmpty ? nil : mean(sameSource)
            }
            var metrics: [String: MetricValue] = [
                "avg_c": .double(round2(average)),
                "sample_count": .int(currentValues.count),
                "baseline_nights": .int(previousNights.count),
                "baseline_window_days": .int(windowDays),
                "baseline_minimum_nights": .int(minimumNights),
                "baseline_method": .string("pulsecommit_mean_of_previous_nights_same_source"),
                "source_name": .string(latest.sourceName),
                "source_bundle_id": .string(latest.sourceBundleID)
            ]
            if previousNights.count >= minimumNights {
                // Each night has equal weight even if one night has more samples.
                let baseline = previousNights.reduce(0, +) / Double(previousNights.count)
                metrics["baseline_c"] = .double(round2(baseline))
                metrics["deviation_c"] = .double(round2(average - baseline))
            }
            return WristTemperatureDay(date: latest.endDate, fragment: SummaryFragment(metrics: metrics, unit: "degC"))
        }
    }

    private static func source(_ sample: QuantitySampleDTO) -> String {
        sample.sourceBundleID + "\u{0}" + sample.sourceName
    }
    private static func mean(_ samples: [QuantitySampleDTO]) -> Double {
        samples.reduce(0) { $0 + $1.value } / Double(samples.count)
    }
    private static func round2(_ value: Double) -> Double {
        let rounded = (value * 100).rounded() / 100
        return rounded == 0 ? 0 : rounded
    }
}
