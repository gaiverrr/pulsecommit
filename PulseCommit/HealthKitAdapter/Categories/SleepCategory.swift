import Foundation
import HealthKit
import HealthCore

public final class SleepCategory: HealthCategory {
    public let id = "sleep"
    public let displayName = "Sleep"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        return try await fetchCategorySamples(
            store: store,
            type: type,
            from: from,
            to: to,
            categoryID: id
        )
    }

    public func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        let lookback = from.addingTimeInterval(-24 * 3600)
        let raw = try await fetch(from: lookback, to: to).compactMap { $0 as? CategorySampleDTO }
        return SleepSessionSample.make(from: raw).filter { $0.sleepEnd >= from && $0.sleepEnd < to }
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let categories = samples.flatMap { sample -> [CategorySampleDTO] in
            if let session = sample as? SleepSessionSample { return session.samples }
            if let category = sample as? CategorySampleDTO { return [category] }
            return []
        }

        var deepIntervals: [DateInterval] = []
        var remIntervals: [DateInterval] = []
        var coreIntervals: [DateInterval] = []
        var awakeIntervals: [DateInterval] = []

        for s in categories {
            guard s.endDate > s.startDate,
                  let stage = HKCategoryValueSleepAnalysis(rawValue: s.value) else { continue }
            let interval = DateInterval(start: s.startDate, end: s.endDate)
            switch stage {
            case .asleepDeep:
                deepIntervals.append(interval)
            case .asleepREM:
                remIntervals.append(interval)
            case .asleepCore, .asleepUnspecified:
                coreIntervals.append(interval)
            case .awake:
                awakeIntervals.append(interval)
            default:
                continue
            }
        }

        // Overlapping samples from multiple sources (Watch + third-party
        // sleep apps) must not double-count, so every metric is the length
        // of the merged interval union, not the sum of raw durations.
        let deep = Self.unionMinutes(deepIntervals)
        let rem = Self.unionMinutes(remIntervals)
        let core = Self.unionMinutes(coreIntervals)
        let awake = Self.unionMinutes(awakeIntervals)
        let duration = Self.unionMinutes(deepIntervals + remIntervals + coreIntervals)
        var result = SummaryFragment(
            metrics: [
                "duration_minutes": .int(Int(duration.rounded())),
                "stage_deep": .int(Int(deep.rounded())),
                "stage_rem": .int(Int(rem.rounded())),
                "stage_core": .int(Int(core.rounded())),
                "stage_awake": .int(Int(awake.rounded()))
            ],
            unit: "min"
        )
        let sessions = SleepSessionSample.make(from: categories)
        let mainSession = sessions.max { lhs, rhs in
            Self.unionMinutes(lhs.asleepSamples.map { DateInterval(start: $0.startDate, end: $0.endDate) }) <
            Self.unionMinutes(rhs.asleepSamples.map { DateInterval(start: $0.startDate, end: $0.endDate) })
        }
        if let mainSession {
            let formatter = ISO8601DateFormatter()
            result.metrics["sleep_start"] = .string(formatter.string(from: mainSession.sleepStart))
            result.metrics["sleep_end"] = .string(formatter.string(from: mainSession.sleepEnd))
        }
        return result
    }

    private static func unionMinutes(_ intervals: [DateInterval]) -> Double {
        guard !intervals.isEmpty else { return 0 }
        let sorted = intervals.sorted { $0.start < $1.start }
        var total = 0.0
        var current = sorted[0]
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                current.end = max(current.end, interval.end)
            } else {
                total += current.duration
                current = interval
            }
        }
        total += current.duration
        return total / 60.0
    }
}
