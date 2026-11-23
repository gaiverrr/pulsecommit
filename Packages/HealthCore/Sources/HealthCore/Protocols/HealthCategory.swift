import Foundation

/// One exportable Health datatype — steps, sleep, workouts, etc.
///
/// Categories sit on the HealthKit-adapter side of the package boundary;
/// the snapshot pipeline asks each enabled category for its samples,
/// hands them to the serializers, then folds per-category
/// `SummaryFragment`s into a single `SummaryDTO`.
///
/// Implementations must be `Sendable`. They typically wrap an
/// `HKHealthStore` and run their queries via `withCheckedThrowingContinuation`.
public protocol HealthCategory: Sendable {
    /// Stable wire identifier used as the `samples/<id>.json` filename
    /// and as the JSON `categoryId` field. Once shipped, treat as
    /// schema and avoid renaming.
    var id: String { get }

    /// Human-readable label for the Categories screen ("Steps",
    /// "Heart Rate Variability"). Not localized in v1.0.
    var displayName: String { get }

    /// Raw per-source samples for the GitHub `samples/*.json` export.
    ///
    /// For cumulative quantity types this can include duplicate iPhone
    /// and Watch samples; they're preserved so analysts can see
    /// per-source attribution downstream.
    ///
    /// - Throws: `CategoryUnavailableError` when HealthKit returns an
    ///   authorization or data-availability error that the user can
    ///   resolve from Settings. Other HealthKit errors propagate.
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO]

    /// Samples for summary computation.
    ///
    /// Cumulative-quantity categories override this to return a single
    /// aggregated DTO whose `value` is HealthKit's cross-source
    /// deduplicated total (via `HKStatisticsQuery(options: .cumulativeSum)`).
    /// The default implementation forwards to `fetch(from:to:)`.
    func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO]

    /// True when `fetchSummarySamples` collapses the requested range into a
    /// single whole-range total. The Normalizer must query such categories
    /// one day at a time over multi-day windows; sample-based categories
    /// keep their single range query. Defaults to `false`; every category
    /// that overrides `fetchSummarySamples` with a statistics query must
    /// also declare `isCumulative: true`.
    var isCumulative: Bool { get }

    /// Fold a sample array into the SummaryDTO contribution for this
    /// category. Must be pure: same input → same output. No HealthKit
    /// access, no `Date()` calls.
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment
}

public extension HealthCategory {
    func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
        try await fetch(from: from, to: to)
    }

    var isCumulative: Bool { false }
}

/// Recoverable error indicating a category cannot be read right now
/// because the user denied authorization or the device lacks the
/// underlying sensor. The orchestrator skips the category and records
/// `reason` in the History entry rather than failing the whole export.
public struct CategoryUnavailableError: Error, Equatable, Sendable {
    public let categoryID: String
    public let reason: String

    public init(categoryID: String, reason: String) {
        self.categoryID = categoryID
        self.reason = reason
    }
}
