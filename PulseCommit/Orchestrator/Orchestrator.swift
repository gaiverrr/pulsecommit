import Foundation
import HealthCore
import os

private let orchestratorLogger = Logger(subsystem: "app.pulsecommit", category: "orchestrator")

actor Orchestrator {
    struct RunResult: Equatable, Sendable {
        let status: HistoryEntry.Status
        let coverageError: HealthHistoryCoverageError?

        init(
            status: HistoryEntry.Status,
            coverageError: HealthHistoryCoverageError? = nil
        ) {
            self.status = status
            self.coverageError = coverageError
        }

        static let success = RunResult(status: .success)
        static let failed = RunResult(status: .failed)
    }

    typealias PipelineDaysOverride = @Sendable (
        _ from: Date,
        _ to: Date,
        _ enabledCategoryIds: Set<String>,
        _ progress: RunProgressHandler?
    ) async throws -> [SnapshotPipelineDay]
    typealias ConsentVerifier = @Sendable (
        _ requirement: ConsentRequirement,
        _ enabledCategoryIds: Set<String>
    ) async -> Bool
    typealias HistoryValidator = @Sendable (
        _ from: Date,
        _ to: Date,
        _ enabledCategoryIds: Set<String>
    ) async throws -> Void

    private let windowResolver: ExportWindowResolver
    private let pipeline: SnapshotPipeline
    private let sinks: [any Sink]
    private let historyStore: HistoryStore
    private let clock: @Sendable () -> Date
    private let isProtectedDataAvailable: @Sendable () async -> Bool
    private let runGate: ExportRunGate
    private let consentRequirements: [String: ConsentRequirement]
    private let consentVerifier: ConsentVerifier
    private let historyValidator: HistoryValidator
    // The real HealthKit pipeline marks a category unavailable for the whole
    // window in one shot, so it can never yield a window where only SOME days
    // are fully unreadable. Tests inject days with per-day
    // `unavailableCategories` here to exercise the partial-window partition.
    private let pipelineDaysOverride: PipelineDaysOverride?

    init(
        windowResolver: ExportWindowResolver,
        pipeline: SnapshotPipeline,
        sinks: [any Sink],
        historyStore: HistoryStore,
        clock: @escaping @Sendable () -> Date = { Date() },
        isProtectedDataAvailable: @escaping @Sendable () async -> Bool = { true },
        runGate: ExportRunGate = ExportRunGate(),
        consentRequirements: [String: ConsentRequirement],
        consentVerifier: @escaping ConsentVerifier,
        historyValidator: @escaping HistoryValidator = { _, _, _ in },
        pipelineDaysOverride: PipelineDaysOverride? = nil
    ) {
        self.windowResolver = windowResolver
        self.pipeline = pipeline
        self.sinks = sinks
        self.historyStore = historyStore
        self.clock = clock
        self.isProtectedDataAvailable = isProtectedDataAvailable
        self.runGate = runGate
        self.consentRequirements = consentRequirements
        self.consentVerifier = consentVerifier
        self.historyValidator = historyValidator
        self.pipelineDaysOverride = pipelineDaysOverride
    }

    var configuredSinkIds: [String] {
        sinks.map(\.id)
    }

    func missingConsentScopes(for request: ExportRequest) async -> [HealthExportConsentScope] {
        var missing: [HealthExportConsentScope] = []
        for sinkID in request.enabledSinkIds.sorted() {
            guard let requirement = consentRequirements[sinkID] else { continue }
            if await !consentVerifier(requirement, request.enabledCategoryIds) {
                missing.append(requirement.scope(for: request.enabledCategoryIds))
            }
        }
        return missing
    }

    func hasCurrentConsent(for request: ExportRequest) async -> Bool {
        await consentIsValid(for: request)
    }

    @discardableResult
    func run(
        _ request: ExportRequest,
        progress: RunProgressHandler? = nil
    ) async -> HistoryEntry.Status {
        await runResult(request, progress: progress).status
    }

    func runResult(
        _ request: ExportRequest,
        progress: RunProgressHandler? = nil
    ) async -> RunResult {
        // An export suspends at every `await`, so actor isolation alone does not
        // prevent two runs from interleaving — and the composition root builds
        // a fresh Orchestrator per run anyway. The shared gate is the only
        // mutual exclusion across Home and App Intents entry points.
        guard await runGate.tryBegin() else {
            let status = await record(
                startedAt: clock(),
                finishedAt: clock(),
                status: .failed,
                sinkIds: Array(request.enabledSinkIds),
                daysCovered: [],
                errorMessage: ExportAlreadyRunningError().errorDescription,
                errorKind: HistoryErrorKind.exportAlreadyRunning
            )
            return RunResult(status: status)
        }
        var coverageError: HealthHistoryCoverageError?
        let status = await execute(
            request,
            progress: progress,
            onCoverageFailure: { coverageError = $0 }
        )
        await runGate.end()
        return RunResult(status: status, coverageError: coverageError)
    }

    private func execute(
        _ request: ExportRequest,
        progress: RunProgressHandler?,
        onCoverageFailure: (HealthHistoryCoverageError) -> Void
    ) async -> HistoryEntry.Status {
        let startedAt = clock()
        if await consentIsValid(for: request) == false {
            return await recordConsentRequired(request: request, startedAt: startedAt)
        }
        // HealthKit is unreadable while the device is locked (Data Protection):
        // queries return empty without an error. Proceeding would publish an
        // empty commit / Telegram message and advance the cursor, silently
        // skipping the day. Fail fast instead — deliver nothing, leave the
        // cursor untouched. The next run with the device unlocked
        // re-covers the day.
        if await isProtectedDataAvailable() == false {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: Array(request.enabledSinkIds),
                daysCovered: [],
                errorMessage: "device locked: HealthKit data is protected and unavailable",
                errorKind: HistoryErrorKind.deviceLocked
            )
        }

        if await consentIsValid(for: request) == false {
            return await recordConsentRequired(request: request, startedAt: startedAt)
        }

        let cursorDate: Date?
        do {
            let store = historyStore
            cursorDate = try await MainActor.run {
                try store.cursor()
            }
        } catch {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: Array(request.enabledSinkIds),
                daysCovered: [],
                errorMessage: "cursor read failed: \(error)"
            )
        }

        let resolution = windowResolver.resolve(
            mode: request.mode,
            cursor: cursorDate,
            now: startedAt
        )

        let from: Date
        let to: Date
        switch resolution {
        case .empty(let reason):
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: Array(request.enabledSinkIds),
                daysCovered: [],
                errorMessage: reason,
                errorKind: HistoryErrorKind.emptyRange
            )
        case .proceed(let f, let t):
            from = f
            to = t
        }

        let activeSinks = sinks.filter { request.enabledSinkIds.contains($0.id) }
        let missingSinkIds = request.enabledSinkIds.subtracting(activeSinks.map(\.id))

        if activeSinks.isEmpty {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: Array(request.enabledSinkIds),
                daysCovered: [],
                errorMessage: "no active sinks configured"
            )
        }

        if !missingSinkIds.isEmpty {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: Array(request.enabledSinkIds),
                daysCovered: [],
                errorMessage: "missing sinks: \(missingSinkIds.sorted().joined(separator: ","))"
            )
        }

        if request.enabledCategoryIds.isEmpty {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: [],
                errorMessage: "no enabled categories"
            )
        }

        let registeredCategoryIds = Set(pipeline.registry.all.map(\.id))
        let missingCategoryIds = request.enabledCategoryIds.subtracting(registeredCategoryIds)
        if !missingCategoryIds.isEmpty {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: [],
                errorMessage: "unknown categories: \(missingCategoryIds.sorted().joined(separator: ","))"
            )
        }

        do {
            try await historyValidator(from, to, request.enabledCategoryIds)
        } catch {
            let coverageError = (error as? HealthHistoryCoverageError) ?? .checkFailed
            onCoverageFailure(coverageError)
            return await recordHistoryCoverageFailure(
                coverageError,
                startedAt: startedAt,
                sinkIds: activeSinks.map(\.id)
            )
        }

        let days: [SnapshotPipelineDay]
        await progress?(.fetching(day: 0, totalDays: 0))
        do {
            if let pipelineDaysOverride {
                days = try await pipelineDaysOverride(from, to, request.enabledCategoryIds, progress)
            } else {
                days = try await pipeline.run(
                    from: from,
                    to: to,
                    enabledCategoryIds: request.enabledCategoryIds,
                    progress: progress
                )
            }
        } catch {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: [],
                errorMessage: "pipeline failed: \(error)"
            )
        }

        // If the device locked while HealthKit was being read, queries return
        // empty (or error) without a reliable signal in the data itself. The
        // start-of-run check above only covers the moment before fetching; a
        // long multi-day backfill can outlive auto-lock. Re-check now, before
        // delivering anything, so a mid-run lock fails cleanly instead of
        // publishing partially-empty days and advancing the cursor.
        if await isProtectedDataAvailable() == false {
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: [],
                errorMessage: "device locked mid-run: HealthKit data became protected before delivery",
                errorKind: HistoryErrorKind.deviceLocked
            )
        }

        do {
            try await historyValidator(from, to, request.enabledCategoryIds)
        } catch {
            let coverageError = (error as? HealthHistoryCoverageError) ?? .checkFailed
            onCoverageFailure(coverageError)
            return await recordHistoryCoverageFailure(
                coverageError,
                startedAt: startedAt,
                sinkIds: activeSinks.map(\.id)
            )
        }

        // Distinguish "readable but quiet" from "could not read". HealthKit
        // returns empty WITHOUT an error when read access is denied, so output
        // emptiness alone cannot prove a problem — a genuinely quiet day, a
        // fresh device, a backfill, or the current day right after
        // midnight all look identical to denial. Only treat a day as failed when
        // there is POSITIVE evidence of an error: every enabled category actually
        // threw (recorded in `unavailableCategories`) on that day. A readable but
        // empty day is exported honestly (an empty commit is a truthful record).
        //
        // If EVERY day is unreadable, fail the whole run and leave the cursor
        // untouched. If only SOME days are unreadable (a transient HealthKit
        // error over part of a multi-day backfill), drop those days rather than
        // publishing them as empty commits/messages — an unreadable day is a
        // failure to read, not a quiet day — and deliver only the readable ones.
        let enabled = request.enabledCategoryIds
        let isFullyUnreadable: (SnapshotPipelineDay) -> Bool = { day in
            enabled.isSubset(of: Set(day.snapshot.unavailableCategories))
        }
        let everythingUnreadable = !days.isEmpty && days.allSatisfy(isFullyUnreadable)
        if everythingUnreadable {
            let names = enabled.sorted().joined(separator: ", ")
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: [],
                errorMessage: "HealthKit could not read any enabled category (\(names)). If you denied access, check Settings → Privacy & Security → Health → Pulse Commit; otherwise this is likely a transient HealthKit error — retry.",
                errorKind: HistoryErrorKind.healthDataUnreadable
            )
        }

        // `everythingUnreadable` already returned when NO day is readable, so a
        // non-empty `days` here always leaves at least one deliverable day.
        let deliverableDays = days.filter { !isFullyUnreadable($0) }

        if await consentIsValid(for: request) == false {
            return await recordConsentRequired(request: request, startedAt: startedAt)
        }

        let dayKeys = deliverableDays.map { DateBucketing.dayKey($0.snapshot.date, in: pipeline.timezone) }
        let totalDays = deliverableDays.count
        await progress?(.serializing(day: 0, totalDays: totalDays))

        var sinkResults: [String: SinkResult] = [:]
        var completedDayKeys: [String] = []
        do {
            for (dayIndex, day) in deliverableDays.enumerated() {
                if await consentIsValid(for: request) == false {
                    return await recordInterruptedByConsent(
                        request: request, startedAt: startedAt,
                        deliveredDays: Array(dayKeys.prefix(dayIndex))
                    )
                }
                try await withThrowingTaskGroup(of: (String, SinkResult).self) { group in
                    for sink in activeSinks {
                        let snapshot = day.snapshot
                        let files = day.files
                        let sinkID = sink.id
                        guard let requirement = consentRequirements[sinkID] else {
                            throw HealthExportAuthorizationError.consentRequired
                        }
                        await progress?(.delivering(sinkID: sinkID, day: dayIndex, totalDays: totalDays))
                        let progressHandler = progress
                        let onAttempt: AttemptHandler?
                        if let handler = progressHandler {
                            let capturedSinkID = sinkID
                            onAttempt = { @Sendable attempt, total, reason in
                                await handler(.retrying(
                                    sinkID: capturedSinkID,
                                    attempt: attempt,
                                    totalAttempts: total,
                                    reason: reason
                                ))
                            }
                        } else {
                            onAttempt = nil
                        }
                        group.addTask {
                            guard await self.consentVerifier(requirement, request.enabledCategoryIds) else {
                                throw HealthExportAuthorizationError.consentRequired
                            }
                            let result = try await sink.deliver(
                                snapshot: snapshot,
                                files: files,
                                onAttempt: onAttempt
                            )
                            return (sink.id, result)
                        }
                    }
                    do {
                        for try await (sinkID, result) in group {
                            sinkResults[sinkID] = result
                        }
                    } catch {
                        group.cancelAll()
                        throw error
                    }
                }
                completedDayKeys.append(dayKeys[dayIndex])
            }
        } catch {
            if error is HealthExportAuthorizationError {
                return await recordInterruptedByConsent(
                    request: request, startedAt: startedAt,
                    deliveredDays: completedDayKeys
                )
            }
            let kind: String? = (error as? GitHubAuthError) == .sessionExpired
                ? HistoryErrorKind.sessionExpired
                : nil
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: dayKeys,
                errorMessage: "sink failed: \(error.localizedDescription)",
                errorKind: kind
            )
        }

        let githubSha: String?
        let githubURL: String?
        let githubBranch: String?
        let telegramRef: String?
        if case .success(let ref, let url) = sinkResults["github"] {
            githubSha = ref
            githubURL = url?.absoluteString
            githubBranch = (activeSinks.first(where: { $0.id == "github" }) as? GitRepoSink)?.branch
        } else {
            githubSha = nil
            githubURL = nil
            githubBranch = nil
        }
        if case .success(let ref, _) = sinkResults["telegram"] {
            telegramRef = ref
        } else {
            telegramRef = nil
        }
        let webhookRef: String?
        if case .success(let ref, _) = sinkResults[WebhookDestinationSink.sinkID] {
            webhookRef = ref
        } else {
            webhookRef = nil
        }

        let advancesCursor: Bool
        switch request.mode {
        case .incremental, .lastDayOnly, .todayLive:
            advancesCursor = true
        case .lastNDays, .range:
            advancesCursor = false
        }

        let finishedAt = clock()
        let sinkIds = activeSinks.map(\.id)

        let store = historyStore
        do {
            if advancesCursor {
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = pipeline.timezone
                let nextCursor = cal.startOfDay(for: startedAt)
                try await MainActor.run {
                    let entry = HistoryEntry(
                        startedAt: startedAt,
                        finishedAt: finishedAt,
                        status: .success,
                        sinks: sinkIds,
                        daysCovered: dayKeys,
                        errorMessage: nil,
                        githubCommitSha: githubSha,
                        githubCommitURLString: githubURL,
                        githubBranch: githubBranch,
                        telegramMessageReference: telegramRef,
                        webhookReference: webhookRef
                    )
                    try store.appendAndAdvanceCursor(entry, cursor: nextCursor)
                }
            } else {
                try await MainActor.run {
                    let entry = HistoryEntry(
                        startedAt: startedAt,
                        finishedAt: finishedAt,
                        status: .success,
                        sinks: sinkIds,
                        daysCovered: dayKeys,
                        errorMessage: nil,
                        githubCommitSha: githubSha,
                        githubCommitURLString: githubURL,
                        githubBranch: githubBranch,
                        telegramMessageReference: telegramRef,
                        webhookReference: webhookRef
                    )
                    try store.append(entry)
                }
            }
        } catch {
            // Error description may include sink names (public) but never tokens.
            orchestratorLogger.error("failed to persist successful run: \(error.localizedDescription, privacy: .public)")
            return await record(
                startedAt: startedAt,
                finishedAt: clock(),
                status: .failed,
                sinkIds: activeSinks.map(\.id),
                daysCovered: dayKeys,
                errorMessage: "persistence failed: \(error)"
            )
        }

        await progress?(.finished)
        return .success
    }

    private func record(
        startedAt: Date,
        finishedAt: Date,
        status: HistoryEntry.Status,
        sinkIds: [String],
        daysCovered: [String],
        errorMessage: String? = nil,
        errorKind: String? = nil,
        githubCommitSha: String? = nil,
        githubCommitURLString: String? = nil,
        telegramMessageReference: String? = nil
    ) async -> HistoryEntry.Status {
        let store = historyStore
        do {
            try await MainActor.run {
                let entry = HistoryEntry(
                    startedAt: startedAt,
                    finishedAt: finishedAt,
                    status: status,
                    sinks: sinkIds,
                    daysCovered: daysCovered,
                    errorMessage: errorMessage,
                    errorKind: errorKind,
                    githubCommitSha: githubCommitSha,
                    githubCommitURLString: githubCommitURLString,
                    telegramMessageReference: telegramMessageReference
                )
                try store.append(entry)
            }
            return status
        } catch {
            orchestratorLogger.error("failed to append history entry (status=\(String(describing: status), privacy: .public)): \(error.localizedDescription, privacy: .public)")
            return status
        }
    }

    private func consentIsValid(for request: ExportRequest) async -> Bool {
        for sinkID in request.enabledSinkIds {
            guard let requirement = consentRequirements[sinkID] else { return false }
            guard await consentVerifier(requirement, request.enabledCategoryIds) else { return false }
        }
        return true
    }

    private func recordHistoryCoverageFailure(
        _ coverageError: HealthHistoryCoverageError,
        startedAt: Date,
        sinkIds: [String]
    ) async -> HistoryEntry.Status {
        let kind = coverageError == .limitedHistory
            ? HistoryErrorKind.limitedHealthHistory
            : HistoryErrorKind.healthHistoryCheckFailed
        return await record(
            startedAt: startedAt,
            finishedAt: clock(),
            status: .failed,
            sinkIds: sinkIds,
            daysCovered: [],
            errorMessage: coverageError.userMessage,
            errorKind: kind
        )
    }

    private func recordConsentRequired(
        request: ExportRequest,
        startedAt: Date
    ) async -> HistoryEntry.Status {
        await record(
            startedAt: startedAt,
            finishedAt: clock(),
            status: .failed,
            sinkIds: Array(request.enabledSinkIds),
            daysCovered: [],
            errorMessage: "Health export consent is required. Open Pulse Commit to review the selected destination.",
            errorKind: HistoryErrorKind.consentRequired
        )
    }

    private func recordInterruptedByConsent(
        request: ExportRequest,
        startedAt: Date,
        deliveredDays: [String]
    ) async -> HistoryEntry.Status {
        await record(
            startedAt: startedAt,
            finishedAt: clock(),
            status: .failed,
            sinkIds: Array(request.enabledSinkIds),
            daysCovered: deliveredDays,
            errorMessage: "Health export consent was revoked during this run. Earlier or in-flight payload requests may have reached the destination.",
            errorKind: HistoryErrorKind.consentRequired
        )
    }
}
