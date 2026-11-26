import XCTest
import HealthCore
@testable import PulseCommit

// MARK: - Test doubles

private struct StubDataCategory: HealthCategory {
    let id: String
    var displayName: String { id }

    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        [QuantitySampleDTO(
            categoryID: id,
            startDate: from.addingTimeInterval(60),
            endDate: from.addingTimeInterval(120),
            value: 1,
            unit: "count",
            sourceName: "iPhone-Test",
            sourceBundleID: "com.apple.health"
        )]
    }

    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SummaryFragment(metrics: ["count": .int(samples.count)], unit: "count")
    }
}

/// A sink whose first `deliver` blocks until the test explicitly releases it,
/// so a second run can be started deterministically while the first is
/// mid-delivery.
private actor HoldingSink: Sink {
    nonisolated let id: String
    private(set) var deliveredCount = 0
    private var started = false
    private var released = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(id: String) {
        self.id = id
    }

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        deliveredCount += 1
        started = true
        if !released {
            await withCheckedContinuation { continuations.append($0) }
        }
        return .success(reference: "held-ref", url: nil)
    }

    func hasStarted() -> Bool { started }

    func release() {
        released = true
        continuations.forEach { $0.resume() }
        continuations.removeAll()
    }

    func callCount() -> Int { deliveredCount }
}

private actor CountingSink: Sink {
    nonisolated let id: String
    private(set) var deliveredCount = 0

    init(id: String) {
        self.id = id
    }

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        deliveredCount += 1
        return .success(reference: "count-ref", url: nil)
    }

    func callCount() -> Int { deliveredCount }
}

// MARK: - Tests

@MainActor
final class OrchestratorConcurrencyTests: XCTestCase {
    private let timezone = TimeZone(identifier: "UTC")!

    private func makePipeline(now: Date) -> SnapshotPipeline {
        SnapshotPipeline(
            registry: CategoryRegistry(categories: [StubDataCategory(id: "steps")]),
            timezone: timezone,
            deviceName: "iPhone-Test",
            appVersion: "1.0.0",
            clock: { now }
        )
    }

    private func makeOrchestrator(
        now: Date,
        sink: any Sink,
        history: HistoryStore,
        gate: ExportRunGate
    ) -> Orchestrator {
        Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(now: now),
            sinks: [sink],
            historyStore: history,
            clock: { now },
            runGate: gate
        )
    }

    private var request: ExportRequest {
        ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        )
    }

    func test_secondConcurrentRun_failsFastWithoutDelivering() async throws {
        // Mirrors production wiring after the fix: the factory builds a fresh
        // Orchestrator per call, but every instance shares ONE ExportRunGate,
        // so a Shortcuts run colliding with a Home-button run cannot deliver
        // twice or double-advance the cursor.
        let now = Date(timeIntervalSince1970: 1_776_600_000)
        let history = try HistoryStore.inMemory()
        let gate = ExportRunGate()

        let holdingSink = HoldingSink(id: "github")
        let secondSink = CountingSink(id: "github")
        let first = makeOrchestrator(now: now, sink: holdingSink, history: history, gate: gate)
        let second = makeOrchestrator(now: now, sink: secondSink, history: history, gate: gate)

        let firstRun = Task { await first.run(self.request) }

        var waited = 0
        while await !holdingSink.hasStarted() {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
            XCTAssertLessThan(waited, 500, "first run never reached its sink")
        }

        let secondStatus = await second.run(request)
        XCTAssertEqual(secondStatus, .failed, "an overlapping run must fail fast, not run concurrently")

        await holdingSink.release()
        let firstStatus = await firstRun.value
        XCTAssertEqual(firstStatus, .success)

        let firstCalls = await holdingSink.callCount()
        let secondCalls = await secondSink.callCount()
        XCTAssertEqual(firstCalls, 1)
        XCTAssertEqual(secondCalls, 0, "the rejected run must not deliver anything")

        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 2)
        let failed = entries.first { $0.status == .failed }
        XCTAssertNotNil(failed, "the rejected run must leave an honest history entry")
        XCTAssertEqual(failed?.errorKind, HistoryErrorKind.exportAlreadyRunning)
        XCTAssertEqual(failed?.errorMessage, ExportAlreadyRunningError().errorDescription)
    }

    func test_sequentialRuns_throughSharedGate_bothSucceed() async throws {
        // The gate blocks only OVERLAP — back-to-back runs stay unaffected.
        let now = Date(timeIntervalSince1970: 1_776_600_000)
        let history = try HistoryStore.inMemory()
        let gate = ExportRunGate()

        let sink1 = CountingSink(id: "github")
        let sink2 = CountingSink(id: "github")
        let first = makeOrchestrator(now: now, sink: sink1, history: history, gate: gate)
        let second = makeOrchestrator(now: now, sink: sink2, history: history, gate: gate)

        let s1 = await first.run(request)
        let s2 = await second.run(request)
        XCTAssertEqual(s1, .success)
        XCTAssertEqual(s2, .success, "the gate must be released after a run finishes")
    }

    func test_gateIsReleased_afterFailedRun() async throws {
        // A run that fails validation must still release the gate.
        let now = Date(timeIntervalSince1970: 1_776_600_000)
        let history = try HistoryStore.inMemory()
        let gate = ExportRunGate()

        let sink = CountingSink(id: "github")
        let orchestrator = makeOrchestrator(now: now, sink: sink, history: history, gate: gate)

        let badRequest = ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: [],
            enabledSinkIds: ["github"]
        )
        let failedStatus = await orchestrator.run(badRequest)
        XCTAssertEqual(failedStatus, .failed)

        let okStatus = await orchestrator.run(request)
        XCTAssertEqual(okStatus, .success, "a failed run must not leave the gate locked")
    }

    func test_gateIsReleasedAfterConsentRejection() async throws {
        let now = Date(timeIntervalSince1970: 1_776_600_000)
        let history = try HistoryStore.inMemory()
        let gate = ExportRunGate()
        let deniedSink = CountingSink(id: "github")
        let requirement = ConsentRequirement(
            sinkID: "github",
            destination: .github(owner: "octocat", repo: "health", branch: "main", subdir: "")
        )
        let denied = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(now: now),
            sinks: [deniedSink],
            historyStore: history,
            clock: { now },
            runGate: gate,
            consentRequirements: ["github": requirement],
            consentVerifier: { _, _ in false }
        )

        let deniedStatus = await denied.run(request)
        XCTAssertEqual(deniedStatus, .failed)

        let acceptedSink = CountingSink(id: "github")
        let accepted = makeOrchestrator(
            now: now, sink: acceptedSink, history: history, gate: gate
        )
        let acceptedStatus = await accepted.run(request)
        XCTAssertEqual(acceptedStatus, .success)
        let calls = await acceptedSink.callCount()
        XCTAssertEqual(calls, 1)
    }

    func test_failedRun_resultCarriesItsOwnEntryEvenWhenNewerSuccessExists() async throws {
        let now = Date(timeIntervalSince1970: 1_776_600_000)
        let history = try HistoryStore.inMemory()
        let gate = ExportRunGate()
        let failing = makeOrchestrator(now: now, sink: CountingSink(id: "github"), history: history, gate: gate)
        let badRequest = ExportRequest(mode: .lastDayOnly, enabledCategoryIds: [], enabledSinkIds: ["github"])

        let failedResult = await failing.runResult(badRequest)
        let failedId = try XCTUnwrap(failedResult.entryId)

        let later = makeOrchestrator(now: now.addingTimeInterval(60), sink: CountingSink(id: "github"), history: history, gate: gate)
        let okResult = await later.runResult(request)
        XCTAssertEqual(okResult.status, .success)

        let newest = try history.recentEntries(limit: 1).first
        XCTAssertNotEqual(newest?.id, failedId, "a newer success exists, so the latest row is not the failed one")
        let looked = try history.entry(id: failedId)
        XCTAssertEqual(looked?.status, .failed)
    }

    func test_rejectedOverlappingRun_resultCarriesItsRecordedEntry() async throws {
        let now = Date(timeIntervalSince1970: 1_776_600_000)
        let history = try HistoryStore.inMemory()
        let gate = ExportRunGate()
        let holdingSink = HoldingSink(id: "github")
        let first = makeOrchestrator(now: now, sink: holdingSink, history: history, gate: gate)
        let second = makeOrchestrator(now: now, sink: CountingSink(id: "github"), history: history, gate: gate)
        let firstRun = Task { await first.runResult(self.request) }
        var waited = 0
        while await !holdingSink.hasStarted() {
            try await Task.sleep(nanoseconds: 10_000_000)
            waited += 1
            XCTAssertLessThan(waited, 500)
        }
        let rejected = await second.runResult(request)
        await holdingSink.release()
        let firstResult = await firstRun.value
        XCTAssertNil(firstResult.entryId)
        let id = try XCTUnwrap(rejected.entryId)
        XCTAssertEqual(try history.entry(id: id)?.errorKind, HistoryErrorKind.exportAlreadyRunning)
    }
}
