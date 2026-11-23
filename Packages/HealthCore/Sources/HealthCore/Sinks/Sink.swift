import Foundation

public enum HealthExportAuthorizationError: Error, Sendable {
    case consentRequired
}

/// A single file to be delivered to a `Sink`. Paths are relative to the
/// snapshot root (e.g. `samples/steps.json`, `routes/abc.gpx`) and use
/// forward slashes regardless of host platform.
public struct FileEntry: Equatable, Sendable {
    public let path: String
    public let data: Data

    public init(path: String, data: Data) {
        self.path = path
        self.data = data
    }
}

/// Outcome of a successful sink delivery.
///
/// `reference` is a sink-specific identifier the History view can quote
/// verbatim — a Git commit SHA for `GitHubSink`, a Telegram `message_id`
/// for `TelegramSink`. `url` is a deep link to the artefact when one
/// exists (commit page on github.com, message permalink on t.me), or
/// `nil` when the sink can't synthesise one.
public enum SinkResult: Equatable, Sendable {
    case success(reference: String, url: URL?)
}

/// A destination for a `DailySnapshot` plus its serialized `FileEntry`
/// payload. Implementations must be `Sendable` and tolerant of being
/// called from any actor.
///
/// Delivery is **atomic from the user's point of view**: either the
/// snapshot lands at the destination as a single observable unit (one
/// Git commit, one Telegram message + ZIP pair) or the implementation
/// throws and leaves the destination unchanged. Partial state is a bug.
/// Per-attempt progress callback for retrying sinks.
///
/// Invoked before each network attempt with the attempt index (1-based),
/// the total number of attempts the sink will make, and a short
/// human-readable reason (e.g. `"starting"`, `"rate limited"`,
/// `"network timeout"`). Always called from the sink's task — callers
/// must not assume any particular actor.
public typealias AttemptHandler = @Sendable (_ attempt: Int, _ totalAttempts: Int, _ reason: String) async -> Void

public protocol Sink: Sendable {
    /// Stable identifier used to disambiguate History entries and
    /// settings rows when more than one sink is configured. Should
    /// match the sink-kind enum case in callers (`"github"`,
    /// `"telegram"`).
    var id: String { get }

    /// Deliver `files` representing `snapshot` to the destination.
    ///
    /// - Throws: A sink-specific error conforming to `LocalizedError` —
    ///   the History view renders `error.localizedDescription` verbatim,
    ///   so messages should be plain-English and actionable.
    /// - Returns: `.success(reference:url:)` on success. There is no
    ///   partial-success case; any failure must throw.
    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult

    /// Variant of `deliver(snapshot:files:)` that emits per-attempt
    /// progress for retrying sinks.
    ///
    /// `onAttempt` is invoked from the sink's task before each network
    /// attempt with `(attempt, totalAttempts, reason)`. Implementations
    /// that never retry should call it exactly once with
    /// `(1, 1, "starting")` or ignore it entirely; the default
    /// extension forwards to the non-progress variant.
    func deliver(
        snapshot: DailySnapshot,
        files: [FileEntry],
        onAttempt: AttemptHandler?
    ) async throws -> SinkResult
}

extension Sink {
    public func deliver(
        snapshot: DailySnapshot,
        files: [FileEntry],
        onAttempt: AttemptHandler?
    ) async throws -> SinkResult {
        try await deliver(snapshot: snapshot, files: files)
    }
}
