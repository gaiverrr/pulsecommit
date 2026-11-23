import Foundation
import HealthKit
import HealthCore

public enum HKCategorySampleMapping {
    public static func map(_ sample: HKCategorySample, categoryID: String) -> CategorySampleDTO {
        let rawMetadata = sample.metadata ?? [:]
        var stringMetadata: [String: String] = [:]
        let isoFormatter = ISO8601DateFormatter()
        for (key, value) in rawMetadata {
            switch value {
            case let s as String:
                stringMetadata[key] = s
            case let n as NSNumber:
                stringMetadata[key] = n.stringValue
            case let d as Date:
                stringMetadata[key] = isoFormatter.string(from: d)
            default:
                continue
            }
        }
        return CategorySampleDTO(
            categoryID: categoryID,
            startDate: sample.startDate,
            endDate: sample.endDate,
            value: sample.value,
            metadata: stringMetadata,
            sourceName: sample.sourceRevision.source.name,
            sourceBundleID: sample.sourceRevision.source.bundleIdentifier
        )
    }
}

public func fetchCategorySamples(
    store: HealthStoreAuthorizing,
    type: HKCategoryType,
    from: Date,
    to: Date,
    categoryID: String
) async throws -> [CategorySampleDTO] {
    let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: .strictStartDate)
    return try await withCheckedThrowingContinuation { continuation in
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
            let categorySamples = (samples as? [HKCategorySample]) ?? []
            let dtos = categorySamples.map { HKCategorySampleMapping.map($0, categoryID: categoryID) }
            continuation.resume(returning: dtos)
        }
        store.execute(query)
    }
}
