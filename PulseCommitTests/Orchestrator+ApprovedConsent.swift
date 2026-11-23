import Foundation
import HealthCore
@testable import PulseCommit

extension Orchestrator {
    init(
        windowResolver: ExportWindowResolver,
        pipeline: SnapshotPipeline,
        sinks: [any Sink],
        historyStore: HistoryStore,
        clock: @escaping @Sendable () -> Date = { Date() },
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool = { true },
        runGate: ExportRunGate = ExportRunGate(),
        historyValidator: @escaping HistoryValidator = { _, _, _ in },
        pipelineDaysOverride: PipelineDaysOverride? = nil
    ) {
        let requirements = Dictionary(uniqueKeysWithValues: sinks.map { sink in
            let destination: HealthExportDestinationIdentity = sink.id == "telegram"
                ? .telegram(chatID: "test-chat", messageThreadID: nil)
                : .github(owner: "test", repo: "test", branch: "main", subdir: "")
            return (sink.id, ConsentRequirement(sinkID: sink.id, destination: destination))
        })
        self.init(
            windowResolver: windowResolver,
            pipeline: pipeline,
            sinks: sinks,
            historyStore: historyStore,
            clock: clock,
            isProtectedDataAvailable: isProtectedDataAvailable,
            runGate: runGate,
            consentRequirements: requirements,
            consentVerifier: { _, _ in true },
            historyValidator: historyValidator,
            pipelineDaysOverride: pipelineDaysOverride
        )
    }
}
