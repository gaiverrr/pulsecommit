import XCTest
import HealthCore
@testable import PulseCommit

final class AutomaticWorkoutDeliveryCoordinatorTests: XCTestCase {
    func test_reconcileClaimsBeforePostAndDoesNotResendDeliveredUUID() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000040")!,
            workout: workout(endingAt: now.addingTimeInterval(-60))
        )
        let source = FakeAutomaticWorkoutSource(candidates: [candidate])
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let sender = RecordingAutomaticWorkoutSender(result: .delivered(messageID: 91), attempts: attempts)
        let configuration = AutomaticWorkoutDeliveryConfiguration(
            scopeID: "scope-A",
            activationDate: now.addingTimeInterval(-3_600),
            timeZoneIdentifier: "UTC"
        )
        let provider = FixedAutomaticWorkoutConfigurationProvider(configuration)
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: source,
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        await coordinator.reconcile()
        await coordinator.reconcile()

        let sentIDs = await sender.sentIDs()
        let record = await attempts.record(for: candidate.id)
        let stateAtSend = await sender.stateObservedAtSend()
        XCTAssertEqual(sentIDs, [candidate.id])
        XCTAssertEqual(record?.state, .delivered(messageID: 91))
        XCTAssertEqual(stateAtSend, .sending)
    }

    func test_reconcileLeavesAmbiguousAttemptUnknownAndNeverAutomaticallyResendsIt() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-10)))
        let source = FakeAutomaticWorkoutSource(candidates: [candidate])
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let sender = RecordingAutomaticWorkoutSender(result: .deliveryUnknown, attempts: attempts)
        let configuration = AutomaticWorkoutDeliveryConfiguration(
            scopeID: "scope-A",
            activationDate: now.addingTimeInterval(-500),
            timeZoneIdentifier: "UTC"
        )
        let provider = FixedAutomaticWorkoutConfigurationProvider(configuration)
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: source,
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        await coordinator.reconcile()
        await coordinator.reconcile()

        let sentCount = await sender.sentIDs().count
        let record = await attempts.record(for: candidate.id)
        XCTAssertEqual(sentCount, 1)
        XCTAssertEqual(record?.state, .deliveryUnknown)
    }

    func test_reconcileRevalidatesScopeAfterQueryAndBeforePost() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-10)))
        let provider = FixedAutomaticWorkoutConfigurationProvider(.init(
            scopeID: "scope-A", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
        ))
        let source = FakeAutomaticWorkoutSource(candidates: [candidate], onFetch: {
            await provider.set(nil)
        })
        let sender = RecordingAutomaticWorkoutSender(result: .delivered(messageID: 1))
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: source,
            sender: sender,
            attempts: InMemoryAutomaticWorkoutAttemptStore(),
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        await coordinator.reconcile()

        let sentIDs = await sender.sentIDs()
        XCTAssertTrue(sentIDs.isEmpty)
    }

    func test_reconcileUsesOnlyActivationThrough72HourWindowAndDefersWhileLocked() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let source = FakeAutomaticWorkoutSource(candidates: [])
        let provider = FixedAutomaticWorkoutConfigurationProvider(.init(
            scopeID: "scope-A", activationDate: now.addingTimeInterval(-300_000), timeZoneIdentifier: "UTC"
        ))
        let locked = LockedState(true)
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: source,
            sender: RecordingAutomaticWorkoutSender(result: .delivered(messageID: 1)),
            attempts: InMemoryAutomaticWorkoutAttemptStore(),
            configuration: { await provider.value() },
            protectedDataAvailable: { await locked.isLocked() == false },
            clock: { now }
        )

        await coordinator.reconcile()
        let lockedRange = await source.lastRange()
        XCTAssertNil(lockedRange)
        await locked.setLocked(false)
        await coordinator.reconcile()

        let range = await source.lastRange()
        XCTAssertEqual(range?.0, now.addingTimeInterval(-72 * 3_600))
        XCTAssertEqual(range?.1, now)
    }

    func test_concurrentReconciliationsCoalesceAndSendUUIDOnce() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-10)))
        let source = SuspendingAutomaticWorkoutSource(candidate: candidate)
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let sender = RecordingAutomaticWorkoutSender(result: .delivered(messageID: 4), attempts: attempts)
        let configuration = AutomaticWorkoutDeliveryConfiguration(
            scopeID: "scope", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
        )
        let provider = FixedAutomaticWorkoutConfigurationProvider(configuration)
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: source,
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        let first = Task { await coordinator.reconcile() }
        await source.waitUntilStarted()
        let overlapping = Task { await coordinator.reconcile() }
        await source.release()
        await first.value
        await overlapping.value

        let sent = await sender.sentIDs()
        XCTAssertEqual(sent, [candidate.id])
    }

    func test_resetDuringSuspendedSendDoesNotRecreateAttemptRecord() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-10)))
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let sender = SuspendingAutomaticWorkoutSender(result: .delivered(messageID: 9))
        let provider = FixedAutomaticWorkoutConfigurationProvider(.init(
            scopeID: "scope", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
        ))
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: FakeAutomaticWorkoutSource(candidates: [candidate]),
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        let reconciliation = Task { await coordinator.reconcile() }
        await sender.waitUntilStarted()
        let oldEpoch = await attempts.epoch()
        let didReset = await attempts.reset()
        XCTAssertTrue(didReset)
        let resetEpoch = await attempts.epoch()
        XCTAssertNotEqual(oldEpoch, resetEpoch)
        await sender.release()
        await reconciliation.value

        let lookup = await attempts.lookup(candidate.id)
        XCTAssertEqual(lookup, .missing)
    }

    func test_revocationDuringSuspendedSendCannotRecordSuccessForOldScope() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-10)))
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let sender = SuspendingAutomaticWorkoutSender(result: .delivered(messageID: 9))
        let provider = FixedAutomaticWorkoutConfigurationProvider(.init(
            scopeID: "scope", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
        ))
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: FakeAutomaticWorkoutSource(candidates: [candidate]),
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        let reconciliation = Task { await coordinator.reconcile() }
        await sender.waitUntilStarted()
        await provider.set(nil)
        await sender.release()
        await reconciliation.value

        let lookup = await attempts.lookup(candidate.id)
        guard case .found(let record) = lookup else { return XCTFail("Expected durable pre-send claim") }
        XCTAssertEqual(record.state, .sending)
    }

    func test_passDeadlineMarksInflightUnknownAndDefersRemainingCandidates() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-20)))
        let second = AutomaticWorkoutCandidate(id: UUID(), workout: workout(endingAt: now.addingTimeInterval(-10)))
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let sender = DeadlineAutomaticWorkoutSender()
        let provider = FixedAutomaticWorkoutConfigurationProvider(.init(
            scopeID: "scope", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
        ))
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: FakeAutomaticWorkoutSource(candidates: [first, second]),
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now },
            passTimeoutNanoseconds: 20_000_000
        )

        let started = Date()
        await coordinator.reconcile()
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        for _ in 0..<20 {
            if case .found(let record) = await attempts.lookup(first.id), record.state == .deliveryUnknown { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .found(let firstRecord) = await attempts.lookup(first.id) else {
            return XCTFail("Expected the claimed request to remain durable")
        }
        XCTAssertEqual(firstRecord.state, .deliveryUnknown)
        let deferredLookup = await attempts.lookup(second.id)
        let firstPassIDs = await sender.sentIDs()
        XCTAssertEqual(deferredLookup, .missing)
        XCTAssertEqual(firstPassIDs, [first.id])

        await coordinator.reconcile()
        for _ in 0..<20 {
            if case .found(let record) = await attempts.lookup(second.id), record.state == .delivered(messageID: 22) { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        guard case .found(let secondRecord) = await attempts.lookup(second.id) else {
            return XCTFail("Expected the deferred candidate to run on the next pass")
        }
        XCTAssertEqual(secondRecord.state, .delivered(messageID: 22))
        let allSentIDs = await sender.sentIDs()
        XCTAssertEqual(allSentIDs, [first.id, second.id])
    }

    func test_latestAndManualRetryAreScopedToCurrentConsentActivation() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldID = UUID()
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        let saved = await attempts.save(.init(
            workoutID: oldID,
            workoutEndDate: now.addingTimeInterval(-100),
            scopeID: "old-destination:old-activation",
            attemptCount: 1,
            updatedAt: now,
            state: .deliveryUnknown
        ))
        XCTAssertTrue(saved)
        let sender = RecordingAutomaticWorkoutSender(result: .delivered(messageID: 3))
        let provider = FixedAutomaticWorkoutConfigurationProvider(.init(
            scopeID: "new-destination:new-activation",
            activationDate: now.addingTimeInterval(-50),
            timeZoneIdentifier: "UTC"
        ))
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: FakeAutomaticWorkoutSource(candidates: []),
            sender: sender,
            attempts: attempts,
            configuration: { await provider.value() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        let newLatest = await attempts.latest(scopeID: "new-destination:new-activation")
        XCTAssertEqual(newLatest, .missing)
        guard case .found = await attempts.latest(scopeID: "old-destination:old-activation") else {
            return XCTFail("Global UUID ledger must retain the old activation record")
        }
        await coordinator.retryUnknown(workoutID: oldID, duplicateRiskAcknowledged: true)
        guard case .found(let unchanged) = await attempts.lookup(oldID) else {
            return XCTFail("Expected old record to remain")
        }
        XCTAssertEqual(unchanged.state, .deliveryUnknown)
        let sentIDs = await sender.sentIDs()
        XCTAssertTrue(sentIDs.isEmpty)
    }

    func test_manualRetryRevalidatesCurrentActivationBeforeChangingLedger() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let current = AutomaticWorkoutDeliveryConfiguration(
            scopeID: "scope", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
        )
        let attempts = InMemoryAutomaticWorkoutAttemptStore()
        _ = await attempts.save(.init(
            workoutID: id,
            workoutEndDate: now.addingTimeInterval(-10),
            scopeID: current.scopeID,
            attemptCount: 1,
            updatedAt: now,
            state: .deliveryUnknown
        ))
        let provider = SequencedAutomaticWorkoutConfigurationProvider([current, nil])
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: FakeAutomaticWorkoutSource(candidates: []),
            sender: RecordingAutomaticWorkoutSender(result: .delivered(messageID: 1)),
            attempts: attempts,
            configuration: { await provider.next() },
            protectedDataAvailable: { true },
            clock: { now }
        )

        await coordinator.retryUnknown(workoutID: id, duplicateRiskAcknowledged: true)

        guard case .found(let record) = await attempts.lookup(id) else {
            return XCTFail("Expected durable unknown record")
        }
        XCTAssertEqual(record.state, .deliveryUnknown)
    }

    private func workout(endingAt end: Date) -> WorkoutDTO {
        WorkoutDTO(
            id: UUID().uuidString,
            type: .outdoorRun,
            startDate: end.addingTimeInterval(-600),
            endDate: end,
            durationMinutes: 10,
            distanceKm: 2,
            activeEnergyKcal: 100,
            avgHeartRate: 140,
            maxHeartRate: 160,
            route: [],
            durationSeconds: 600,
            distanceMeters: 2_000
        )
    }
}

private actor SuspendingAutomaticWorkoutSource: AutomaticWorkoutQuerying {
    let candidate: AutomaticWorkoutCandidate
    private var started = false
    private var hasSuspended = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(candidate: AutomaticWorkoutCandidate) { self.candidate = candidate }

    func workouts(from: Date, to: Date) async throws -> [AutomaticWorkoutCandidate] {
        if hasSuspended { return [candidate] }
        hasSuspended = true
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return [candidate]
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor FakeAutomaticWorkoutSource: AutomaticWorkoutQuerying {
    let candidates: [AutomaticWorkoutCandidate]
    let onFetch: (@Sendable () async -> Void)?
    private var range: (Date, Date)?

    init(candidates: [AutomaticWorkoutCandidate], onFetch: (@Sendable () async -> Void)? = nil) {
        self.candidates = candidates
        self.onFetch = onFetch
    }

    func workouts(from: Date, to: Date) async throws -> [AutomaticWorkoutCandidate] {
        range = (from, to)
        await onFetch?()
        return candidates
    }

    func lastRange() -> (Date, Date)? { range }
}

private actor RecordingAutomaticWorkoutSender: AutomaticWorkoutSending {
    let result: AutomaticWorkoutSendResult
    let attempts: InMemoryAutomaticWorkoutAttemptStore?
    private var ids: [UUID] = []
    private var observed: AutomaticWorkoutAttemptState?

    init(result: AutomaticWorkoutSendResult, attempts: InMemoryAutomaticWorkoutAttemptStore? = nil) {
        self.result = result
        self.attempts = attempts
    }

    func send(_ candidate: AutomaticWorkoutCandidate, scopeID: String, timeZoneIdentifier: String) async -> AutomaticWorkoutSendResult {
        ids.append(candidate.id)
        observed = await attempts?.record(for: candidate.id)?.state
        return result
    }

    func sentIDs() -> [UUID] { ids }
    func stateObservedAtSend() -> AutomaticWorkoutAttemptState? { observed }
}

private actor SuspendingAutomaticWorkoutSender: AutomaticWorkoutSending {
    let result: AutomaticWorkoutSendResult
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(result: AutomaticWorkoutSendResult) { self.result = result }

    func send(_ candidate: AutomaticWorkoutCandidate, scopeID: String, timeZoneIdentifier: String) async -> AutomaticWorkoutSendResult {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        return result
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor DeadlineAutomaticWorkoutSender: AutomaticWorkoutSending {
    private var ids: [UUID] = []

    func send(_ candidate: AutomaticWorkoutCandidate, scopeID: String, timeZoneIdentifier: String) async -> AutomaticWorkoutSendResult {
        ids.append(candidate.id)
        if ids.count == 1 {
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return .delivered(messageID: 11)
            } catch {
                return .deliveryUnknown
            }
        }
        return .delivered(messageID: 22)
    }

    func sentIDs() -> [UUID] { ids }
}

private actor FixedAutomaticWorkoutConfigurationProvider {
    private var configuration: AutomaticWorkoutDeliveryConfiguration?
    init(_ configuration: AutomaticWorkoutDeliveryConfiguration?) { self.configuration = configuration }
    func value() -> AutomaticWorkoutDeliveryConfiguration? { configuration }
    func set(_ value: AutomaticWorkoutDeliveryConfiguration?) { configuration = value }
}

private actor SequencedAutomaticWorkoutConfigurationProvider {
    private var values: [AutomaticWorkoutDeliveryConfiguration?]
    init(_ values: [AutomaticWorkoutDeliveryConfiguration?]) { self.values = values }
    func next() -> AutomaticWorkoutDeliveryConfiguration? {
        values.isEmpty ? nil : values.removeFirst()
    }
}

private actor LockedState {
    private var value: Bool
    init(_ value: Bool) { self.value = value }
    func isLocked() -> Bool { value }
    func setLocked(_ value: Bool) { self.value = value }
}
