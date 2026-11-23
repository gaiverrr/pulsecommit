import Foundation

/// Serializes export runs across every entry point. The composition root
/// builds a fresh `Orchestrator` per run (sinks depend on current
/// preferences), so mutual exclusion cannot live inside the orchestrator
/// instance — Home-button taps and App Intents / Shortcuts automations must
/// share ONE gate or two runs race the same GitHub branch and SwiftData
/// cursor. GitHubSink additionally documents a non-concurrent
/// `deliver` invariant that this gate upholds.
actor ExportRunGate {
    private var isRunning = false

    /// Returns `false` without waiting when a run is already in flight —
    /// overlapping runs fail fast rather than queue (a queued Shortcuts run
    /// would re-export the same window right after the first finished).
    func tryBegin() -> Bool {
        if isRunning { return false }
        isRunning = true
        return true
    }

    func end() {
        isRunning = false
    }
}

struct ExportAlreadyRunningError: Error, LocalizedError {
    var errorDescription: String? {
        "export already running: another export is in progress — wait for it to finish and retry"
    }
}

extension HistoryErrorKind {
    /// The run was rejected because another export was already in flight
    /// (e.g. a Shortcuts automation fired while a manual export was running).
    /// Nothing was delivered and the cursor was left untouched.
    static let exportAlreadyRunning = "exportAlreadyRunning"
}
