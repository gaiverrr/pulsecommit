import Foundation
@testable import HealthCore

enum SampleFixtures {
    static func iso(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)!
    }

    static func quantity(
        categoryID: String,
        start: String,
        end: String? = nil,
        value: Double,
        unit: String = "count",
        sourceName: String = "iPhone",
        sourceBundleID: String = "com.apple.health"
    ) -> QuantitySampleDTO {
        let s = iso(start)
        let e = end.map(iso) ?? s
        return QuantitySampleDTO(
            categoryID: categoryID,
            startDate: s,
            endDate: e,
            value: value,
            unit: unit,
            sourceName: sourceName,
            sourceBundleID: sourceBundleID
        )
    }
}

struct FixtureCategory: HealthCategory {
    let id: String
    let displayName: String
    let samples: [any SampleDTO]
    let summarizer: @Sendable ([any SampleDTO]) -> SummaryFragment
    let fetchDelayNanoseconds: UInt64

    init(
        id: String,
        displayName: String = "Stub",
        samples: [any SampleDTO] = [],
        summarizer: @escaping @Sendable ([any SampleDTO]) -> SummaryFragment = { _ in SummaryFragment() },
        fetchDelayNanoseconds: UInt64 = 0
    ) {
        self.id = id
        self.displayName = displayName
        self.samples = samples
        self.summarizer = summarizer
        self.fetchDelayNanoseconds = fetchDelayNanoseconds
    }

    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        if fetchDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: fetchDelayNanoseconds)
        }
        return samples.filter { $0.startDate >= from && $0.startDate < to }
    }

    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        summarizer(samples)
    }
}
