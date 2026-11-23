import Foundation
import HealthKit
import HealthCore

public final class StateOfMindCategory: HealthCategory {
    public let id = "state_of_mind"
    public let displayName = "State of Mind"

    private let store: any HealthStoreAuthorizing

    public init(store: any HealthStoreAuthorizing) {
        self.store = store
    }

    public func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        guard #available(iOS 18.0, *) else {
            throw CategoryUnavailableError(categoryID: id, reason: "HKStateOfMind requires iOS 18")
        }
        let type = HKObjectType.stateOfMindType()
        let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
        let categoryID = id
        let samples: [HKStateOfMind] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKStateOfMind]) ?? [])
            }
            store.execute(query)
        }
        return samples.map { sample -> StateOfMindSampleDTO in
            let labels = sample.labels.map { Self.stringify($0) }
            let entry = StateOfMindEntryDTO(
                time: sample.startDate,
                valence: sample.valence,
                labels: labels
            )
            return StateOfMindSampleDTO(
                categoryID: categoryID,
                sourceName: sample.sourceRevision.source.name,
                sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
                entry: entry
            )
        }
    }

    @available(iOS 18.0, *)
    static func stringify(_ label: HKStateOfMind.Label) -> String {
        "label_\(label.rawValue)"
    }

    public func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        let entries = samples.compactMap { ($0 as? StateOfMindSampleDTO)?.entry }
        let count = entries.count
        let avgValence: Double
        if count > 0 {
            let total = entries.reduce(0.0) { $0 + $1.valence }
            avgValence = (total / Double(count) * 1000).rounded() / 1000
        } else {
            avgValence = 0
        }
        return SummaryFragment(
            metrics: [
                "count": .int(count),
                "avg_valence": .double(avgValence)
            ],
            unit: "entries"
        )
    }
}
