import Foundation
import HealthCore

struct AutomaticWorkoutCandidate: Equatable, Sendable {
    let id: UUID
    let workout: WorkoutDTO
}

protocol AutomaticWorkoutQuerying: Sendable {
    func workouts(from: Date, to: Date) async throws -> [AutomaticWorkoutCandidate]
}

enum AutomaticWorkoutSendResult: Equatable, Sendable {
    case delivered(messageID: Int)
    case rejected(retryAfter: Date?)
    case deliveryUnknown
}

protocol AutomaticWorkoutSending: Sendable {
    func send(
        _ candidate: AutomaticWorkoutCandidate,
        scopeID: String,
        timeZoneIdentifier: String
    ) async -> AutomaticWorkoutSendResult
}

struct AutomaticWorkoutDeliveryConfiguration: Equatable, Sendable {
    let scopeID: String
    let activationDate: Date
    let timeZoneIdentifier: String
}

enum AutomaticWorkoutAttemptState: Codable, Equatable, Sendable {
    case sending
    case delivered(messageID: Int)
    case rejected(retryAfter: Date?)
    case deliveryUnknown
}

struct AutomaticWorkoutAttemptRecord: Codable, Equatable, Sendable {
    let workoutID: UUID
    let workoutEndDate: Date
    let scopeID: String
    var attemptCount: Int
    var updatedAt: Date
    var state: AutomaticWorkoutAttemptState
}

protocol AutomaticWorkoutAttemptStoring: Sendable {
    func epoch() async -> UUID?
    func lookup(_ id: UUID) async -> AutomaticWorkoutAttemptLookup
    func latest(scopeID: String) async -> AutomaticWorkoutAttemptLookup
    func save(_ record: AutomaticWorkoutAttemptRecord) async -> Bool
    func prune(olderThan cutoff: Date) async -> Bool
    func reset() async -> Bool
}

enum AutomaticWorkoutAttemptLookup: Equatable, Sendable {
    case found(AutomaticWorkoutAttemptRecord)
    case missing
    case unavailable
}

actor InMemoryAutomaticWorkoutAttemptStore: AutomaticWorkoutAttemptStoring {
    private var records: [UUID: AutomaticWorkoutAttemptRecord] = [:]
    private var currentEpoch = UUID()

    func epoch() -> UUID? { currentEpoch }

    func lookup(_ id: UUID) -> AutomaticWorkoutAttemptLookup {
        records[id].map(AutomaticWorkoutAttemptLookup.found) ?? .missing
    }

    func record(for id: UUID) -> AutomaticWorkoutAttemptRecord? { records[id] }

    func latest(scopeID: String) -> AutomaticWorkoutAttemptLookup {
        records.values.filter { $0.scopeID == scopeID }.max(by: { $0.updatedAt < $1.updatedAt })
            .map(AutomaticWorkoutAttemptLookup.found) ?? .missing
    }

    func save(_ record: AutomaticWorkoutAttemptRecord) -> Bool {
        records[record.workoutID] = record
        return true
    }

    func prune(olderThan cutoff: Date) -> Bool {
        records = records.filter { $0.value.workoutEndDate >= cutoff }
        return true
    }

    func reset() -> Bool {
        records.removeAll()
        currentEpoch = UUID()
        return true
    }
}

actor AutomaticWorkoutDeliveryCoordinator {
    static let catchUpInterval: TimeInterval = 72 * 3_600
    static let retentionInterval: TimeInterval = 7 * 24 * 3_600
    static let maximumConfirmedAttempts = 3

    private let source: any AutomaticWorkoutQuerying
    private let sender: any AutomaticWorkoutSending
    private let attempts: any AutomaticWorkoutAttemptStoring
    private let configuration: @Sendable () async -> AutomaticWorkoutDeliveryConfiguration?
    private let protectedDataAvailable: @Sendable () async -> Bool
    private let clock: @Sendable () -> Date
    private let passTimeoutNanoseconds: UInt64
    private let stateDidChange: @Sendable () async -> Void
    private var activePass: Task<Void, Never>?
    private var reconcileAgain = false

    init(
        source: any AutomaticWorkoutQuerying,
        sender: any AutomaticWorkoutSending,
        attempts: any AutomaticWorkoutAttemptStoring,
        configuration: @escaping @Sendable () async -> AutomaticWorkoutDeliveryConfiguration?,
        protectedDataAvailable: @escaping @Sendable () async -> Bool,
        clock: @escaping @Sendable () -> Date = { Date() },
        passTimeoutNanoseconds: UInt64 = 15_000_000_000,
        stateDidChange: @escaping @Sendable () async -> Void = {}
    ) {
        self.source = source
        self.sender = sender
        self.attempts = attempts
        self.configuration = configuration
        self.protectedDataAvailable = protectedDataAvailable
        self.clock = clock
        self.passTimeoutNanoseconds = passTimeoutNanoseconds
        self.stateDidChange = stateDidChange
    }

    func reconcile() async {
        if activePass != nil {
            reconcileAgain = true
            return
        }
        let pass = Task { await self.runReconciliationPasses() }
        activePass = pass
        await AutomaticWorkoutPassWaiter.wait(
            for: pass,
            timeoutNanoseconds: passTimeoutNanoseconds
        )
    }

    private func runReconciliationPasses() async {
        repeat {
            reconcileAgain = false
            await performReconciliation()
        } while reconcileAgain && !Task.isCancelled
        activePass = nil
    }

    func retryUnknown(workoutID: UUID, duplicateRiskAcknowledged: Bool) async {
        guard duplicateRiskAcknowledged else { return }
        guard let current = await configuration() else { return }
        guard let attemptEpoch = await attempts.epoch() else { return }
        guard case .found(var record) = await attempts.lookup(workoutID),
              record.state == .deliveryUnknown,
              record.scopeID == current.scopeID else { return }
        record.state = .rejected(retryAfter: clock())
        record.updatedAt = clock()
        guard await attempts.epoch() == attemptEpoch,
              await configuration() == current else { return }
        guard await saveAndNotify(record) else { return }
        await reconcile()
    }

    private func performReconciliation() async {
        guard !Task.isCancelled, await protectedDataAvailable(),
              let initial = await configuration() else { return }
        let now = clock()
        let oldestRecent = now.addingTimeInterval(-Self.catchUpInterval)
        let from = max(initial.activationDate, oldestRecent)
        guard from <= now else { return }
        guard await attempts.prune(olderThan: now.addingTimeInterval(-Self.retentionInterval)) else { return }

        let candidates: [AutomaticWorkoutCandidate]
        do {
            candidates = try await source.workouts(from: from, to: now)
        } catch {
            return
        }

        for candidate in candidates.sorted(by: { $0.workout.endDate < $1.workout.endDate }) {
            guard !Task.isCancelled, await protectedDataAvailable() else { return }
            guard eligible(candidate, from: from, through: now) else { continue }
            guard let current = await configuration(), current == initial else { return }
            guard let attemptEpoch = await attempts.epoch() else { return }
            let lookup = await attempts.lookup(candidate.id)
            switch lookup {
            case .unavailable:
                return
            case .found(var existing):
                if existing.state == .sending {
                    existing.state = .deliveryUnknown
                    existing.updatedAt = now
                    guard await saveAndNotify(existing) else { return }
                    continue
                }
                if !mayRetry(existing, at: now) { continue }
            case .missing:
                break
            }

            let priorCount: Int
            if case .found(let existing) = lookup { priorCount = existing.attemptCount }
            else { priorCount = 0 }
            let claim = AutomaticWorkoutAttemptRecord(
                workoutID: candidate.id,
                workoutEndDate: candidate.workout.endDate,
                scopeID: current.scopeID,
                attemptCount: priorCount + 1,
                updatedAt: now,
                state: .sending
            )
            guard await saveAndNotify(claim) else { return }
            guard await attempts.epoch() == attemptEpoch,
                  !Task.isCancelled, await protectedDataAvailable(),
                  await configuration() == current else {
                var stopped = claim
                stopped.state = .rejected(retryAfter: nil)
                if await attempts.epoch() == attemptEpoch {
                    _ = await saveAndNotify(stopped)
                }
                return
            }

            let outcome = await sender.send(
                candidate,
                scopeID: current.scopeID,
                timeZoneIdentifier: current.timeZoneIdentifier
            )
            var completed = claim
            completed.updatedAt = clock()
            switch outcome {
            case .delivered(let messageID): completed.state = .delivered(messageID: messageID)
            case .rejected(let retryAfter): completed.state = .rejected(retryAfter: retryAfter)
            case .deliveryUnknown: completed.state = .deliveryUnknown
            }
            guard await attempts.epoch() == attemptEpoch,
                  await configuration() == current else { return }
            guard await saveAndNotify(completed) else { return }
        }
    }

    private func saveAndNotify(_ record: AutomaticWorkoutAttemptRecord) async -> Bool {
        guard await attempts.save(record) else { return false }
        await stateDidChange()
        return true
    }

    private func eligible(_ candidate: AutomaticWorkoutCandidate, from: Date, through now: Date) -> Bool {
        let workout = candidate.workout
        guard workout.startDate.timeIntervalSinceReferenceDate.isFinite,
              workout.endDate.timeIntervalSinceReferenceDate.isFinite,
              workout.endDate >= from,
              workout.endDate <= now,
              workout.endDate > workout.startDate,
              let duration = workout.durationSeconds,
              duration.isFinite,
              duration > 0 else { return false }
        return true
    }

    private func mayRetry(_ record: AutomaticWorkoutAttemptRecord, at now: Date) -> Bool {
        switch record.state {
        case .delivered, .deliveryUnknown, .sending:
            return false
        case .rejected(let retryAfter):
            guard record.attemptCount < Self.maximumConfirmedAttempts else { return false }
            return retryAfter.map { $0 <= now } ?? true
        }
    }
}

private final class AutomaticWorkoutPassWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    static func wait(for task: Task<Void, Never>, timeoutNanoseconds: UInt64) async {
        let waiter = AutomaticWorkoutPassWaiter()
        Task {
            await task.value
            waiter.finish()
        }
        Task {
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            task.cancel()
            waiter.finish()
        }
        await withTaskCancellationHandler {
            await waiter.suspend()
        } onCancel: {
            task.cancel()
            waiter.finish()
        }
    }

    private func suspend() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if finished {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    private func finish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}
