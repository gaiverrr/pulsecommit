import Foundation
import HealthKit
import HealthCore

// Summary-only samples are anchored at the end of sleep so Normalizer keeps
// an overnight session on its wake date. Raw HealthKit timestamps stay intact.
struct SleepSessionSample: SampleDTO {
    let samples: [CategorySampleDTO]
    let sleepStart: Date
    let sleepEnd: Date
    var categoryID: String { "sleep" }
    var startDate: Date { sleepEnd }
    var endDate: Date { sleepEnd }
    var sourceName: String { "HealthKit (sleep session)" }
    var sourceBundleID: String { "app.pulsecommit" }

    var asleepSamples: [CategorySampleDTO] { samples.filter(Self.isAsleep) }

    static func isAsleep(_ sample: CategorySampleDTO) -> Bool {
        guard sample.endDate > sample.startDate,
              let stage = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return false }
        switch stage {
        case .asleepCore, .asleepDeep, .asleepREM, .asleepUnspecified: return true
        default: return false
        }
    }

    static func make(from samples: [CategorySampleDTO]) -> [SleepSessionSample] {
        let ordered = samples.filter {
            $0.endDate > $0.startDate && (isAsleep($0) || $0.value == HKCategoryValueSleepAnalysis.awake.rawValue)
        }.sorted { $0.startDate < $1.startDate }
        var groups: [[CategorySampleDTO]] = []
        var end: Date?
        for sample in ordered {
            // A three-hour gap separates nights and naps without splitting
            // the ordinary awake intervals within an overnight session.
            if let previousEnd = end, sample.startDate.timeIntervalSince(previousEnd) < 3 * 3600 {
                groups[groups.count - 1].append(sample)
                end = max(previousEnd, sample.endDate)
            } else {
                groups.append([sample])
                end = sample.endDate
            }
        }
        return groups.compactMap { group in
            let asleep = group.filter(isAsleep)
            guard let start = asleep.map(\.startDate).min(), let end = asleep.map(\.endDate).max() else { return nil }
            return SleepSessionSample(samples: group, sleepStart: start, sleepEnd: end)
        }
    }
}
