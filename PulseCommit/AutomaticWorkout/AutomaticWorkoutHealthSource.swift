import Foundation
import HealthCore
import HealthKit

struct AutomaticWorkoutHealthSource: AutomaticWorkoutQuerying {
    let store: any HealthStoreAuthorizing
    let historyProvider: any HealthHistoryDateProviding
    let queryTimeoutNanoseconds: UInt64

    init(
        store: any HealthStoreAuthorizing,
        historyProvider: any HealthHistoryDateProviding,
        queryTimeoutNanoseconds: UInt64 = 15_000_000_000
    ) {
        self.store = store
        self.historyProvider = historyProvider
        self.queryTimeoutNanoseconds = queryTimeoutNanoseconds
    }

    func workouts(from: Date, to: Date) async throws -> [AutomaticWorkoutCandidate] {
        let predicate = HKQuery.predicateForSamples(
            withStart: from,
            end: to,
            options: .strictEndDate
        )
        let operation = TimedWorkoutFetchOperation(
            store: store,
            historyProvider: historyProvider,
            predicate: predicate,
            coverageStart: from,
            timeoutNanoseconds: queryTimeoutNanoseconds
        )
        let workouts = try await operation.value()
        return workouts.map {
            AutomaticWorkoutCandidate(id: $0.uuid, workout: HKWorkoutMapping.map($0))
        }
    }
}

enum AutomaticWorkoutHealthSourceError: Error, Equatable {
    case timedOut
}

private final class TimedWorkoutFetchOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let store: any HealthStoreAuthorizing
    private let historyProvider: any HealthHistoryDateProviding
    private let predicate: NSPredicate
    private let coverageStart: Date
    private let timeoutNanoseconds: UInt64
    private var continuation: CheckedContinuation<[HKWorkout], Error>?
    private var workTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var finished = false

    init(
        store: any HealthStoreAuthorizing,
        historyProvider: any HealthHistoryDateProviding,
        predicate: NSPredicate,
        coverageStart: Date,
        timeoutNanoseconds: UInt64
    ) {
        self.store = store
        self.historyProvider = historyProvider
        self.predicate = predicate
        self.coverageStart = coverageStart
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func value() async throws -> [HKWorkout] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                lock.unlock()
                start()
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    private func start() {
        let store = store
        let historyProvider = historyProvider
        let predicate = predicate
        let coverageStart = coverageStart
        let work = Task { [weak self] in
            do {
                if historyProvider.supportsLimitedHistoryLookup {
                    let workoutType = HKObjectType.workoutType()
                    let boundaries: [HKObjectType: Date]?
                    do {
                        boundaries = try await historyProvider.earliestAuthorizedSampleDates(for: [workoutType])
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        throw HealthHistoryCoverageError.checkFailed
                    }
                    if let boundary = boundaries?[workoutType], boundary > coverageStart {
                        throw HealthHistoryCoverageError.limitedHistory
                    }
                }
                try Task.checkCancellation()
                let query = WorkoutQueryOperation(store: store, predicate: predicate)
                self?.finish(.success(try await query.value()))
            } catch {
                self?.finish(.failure(error))
            }
        }
        let timeoutNanoseconds = timeoutNanoseconds
        let timeout = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                self?.finish(.failure(AutomaticWorkoutHealthSourceError.timedOut))
            } catch {}
        }
        install(work: work, timeout: timeout)
    }

    private func install(work: Task<Void, Never>, timeout: Task<Void, Never>) {
        lock.lock()
        if finished {
            lock.unlock()
            work.cancel()
            timeout.cancel()
            return
        }
        workTask = work
        timeoutTask = timeout
        lock.unlock()
    }

    private func finish(_ result: Result<[HKWorkout], Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = continuation
        let work = workTask
        let timeout = timeoutTask
        self.continuation = nil
        workTask = nil
        timeoutTask = nil
        lock.unlock()
        work?.cancel()
        timeout?.cancel()
        continuation?.resume(with: result)
    }
}

private final class WorkoutQueryOperation: @unchecked Sendable {
    private let lock = NSLock()
    private let store: any HealthStoreAuthorizing
    private let predicate: NSPredicate
    private var query: HKSampleQuery?
    private var continuation: CheckedContinuation<[HKWorkout], Error>?
    private var finished = false

    init(store: any HealthStoreAuthorizing, predicate: NSPredicate) {
        self.store = store
        self.predicate = predicate
    }

    func value() async throws -> [HKWorkout] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: HKObjectType.workoutType(),
                    predicate: predicate,
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
                ) { [weak self] _, samples, error in
                    if let error { self?.finish(.failure(error)); return }
                    self?.finish(.success((samples as? [HKWorkout]) ?? []))
                }
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.query = query
                self.continuation = continuation
                lock.unlock()
                store.execute(query)
            }
        } onCancel: {
            cancel()
        }
    }

    private func cancel() {
        lock.lock()
        let query = self.query
        lock.unlock()
        if let query { store.stop(query) }
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<[HKWorkout], Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        self.continuation = nil
        self.query = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
