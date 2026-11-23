import Foundation
import HealthKit
import UIKit

protocol AutomaticWorkoutObserverHealthStore: Sendable {
    func execute(_ query: HKQuery)
    func stop(_ query: HKQuery)
    func enableWorkoutBackgroundDelivery(completion: @escaping @Sendable (Bool, Error?) -> Void)
    func disableWorkoutBackgroundDelivery(completion: @escaping @Sendable (Bool, Error?) -> Void)
}

extension HealthStoreClient: AutomaticWorkoutObserverHealthStore {}

typealias AutomaticWorkoutObserverCompletion = () -> Void
typealias AutomaticWorkoutObserverUpdateHandler = @Sendable (
    _ error: Error?,
    _ completion: @escaping AutomaticWorkoutObserverCompletion
) -> Void
typealias AutomaticWorkoutObserverFactory = (
    _ handler: @escaping AutomaticWorkoutObserverUpdateHandler
) -> HKObserverQuery

@MainActor
protocol AutomaticWorkoutBackgroundTaskManaging: AnyObject {
    func begin(expiration: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier
    func end(_ identifier: UIBackgroundTaskIdentifier)
}

@MainActor
final class ApplicationAutomaticWorkoutBackgroundTaskManager: AutomaticWorkoutBackgroundTaskManaging {
    func begin(expiration: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        UIApplication.shared.beginBackgroundTask(withName: "Automatic workout", expirationHandler: expiration)
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) {
        UIApplication.shared.endBackgroundTask(identifier)
    }
}

@MainActor
final class AutomaticWorkoutObserverController {
    private let store: any AutomaticWorkoutObserverHealthStore
    private let preferences: PreferencesStore
    private let reconcileAction: @Sendable () async -> Void
    private let observerFactory: AutomaticWorkoutObserverFactory
    private let backgroundTasks: any AutomaticWorkoutBackgroundTaskManaging
    private let protectedDataAvailable: @MainActor () -> Bool
    private let callbackTimeoutNanoseconds: UInt64
    private var observer: HKObserverQuery?

    init(
        store: any AutomaticWorkoutObserverHealthStore,
        preferences: PreferencesStore,
        reconcileAction: @escaping @Sendable () async -> Void,
        observerFactory: @escaping AutomaticWorkoutObserverFactory = { handler in
            HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
                handler(error, completion)
            }
        },
        backgroundTasks: (any AutomaticWorkoutBackgroundTaskManaging)? = nil,
        protectedDataAvailable: @escaping @MainActor () -> Bool = { UIApplication.shared.isProtectedDataAvailable },
        callbackTimeoutNanoseconds: UInt64 = 17_000_000_000
    ) {
        self.store = store
        self.preferences = preferences
        self.reconcileAction = reconcileAction
        self.observerFactory = observerFactory
        self.backgroundTasks = backgroundTasks ?? ApplicationAutomaticWorkoutBackgroundTaskManager()
        self.protectedDataAvailable = protectedDataAvailable
        self.callbackTimeoutNanoseconds = callbackTimeoutNanoseconds
    }

    convenience init(
        store: any AutomaticWorkoutObserverHealthStore,
        preferences: PreferencesStore,
        coordinator: AutomaticWorkoutDeliveryCoordinator
    ) {
        self.init(store: store, preferences: preferences, reconcileAction: {
            await coordinator.reconcile()
        })
    }

    /// Called directly from application(_:didFinishLaunchingWithOptions:).
    /// Query registration itself is synchronous so HealthKit can deliver a
    /// background launch before SwiftUI creates its first scene.
    func registerSynchronouslyIfOptedIn() {
        guard preferences.automaticWorkoutTelegramEnabled else { return }
        registerObserverIfNeeded()
        enableBackgroundDelivery()
    }

    func refreshRegistration() {
        if preferences.automaticWorkoutTelegramEnabled {
            registerObserverIfNeeded()
            enableBackgroundDelivery()
            reconcile()
        } else {
            stopObserver()
        }
    }

    func reconcile() {
        guard preferences.automaticWorkoutTelegramEnabled,
              protectedDataAvailable() else { return }
        Task { await reconcileAction() }
    }

    private func registerObserverIfNeeded() {
        guard observer == nil else { return }
        let query = observerFactory { [weak self] error, completion in
            let once = ObserverCompletionOnce(completion)
            guard error == nil else { once.call(); return }
            Task { @MainActor [weak self] in
                guard let self else { once.call(); return }
                guard self.preferences.automaticWorkoutTelegramEnabled,
                      self.protectedDataAvailable() else {
                    once.call()
                    return
                }
                let run = ObserverBackgroundRun(completion: once, manager: self.backgroundTasks)
                let work = Task { await self.reconcileAction() }
                run.start(task: work, timeoutNanoseconds: self.callbackTimeoutNanoseconds)
                await run.waitUntilFinished()
            }
        }
        observer = query
        store.execute(query)
    }

    private func enableBackgroundDelivery() {
        store.enableWorkoutBackgroundDelivery { [weak self] success, _ in
            Task { @MainActor in
                self?.preferences.automaticWorkoutRegistrationFailed = !success
            }
        }
    }

    private func stopObserver() {
        if let observer { store.stop(observer) }
        observer = nil
        store.disableWorkoutBackgroundDelivery { _, _ in }
    }
}

@MainActor
private final class ObserverBackgroundRun {
    private let completion: ObserverCompletionOnce
    private let manager: any AutomaticWorkoutBackgroundTaskManaging
    private var task: Task<Void, Never>?
    private var completionMonitor: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var backgroundID: UIBackgroundTaskIdentifier = .invalid
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(completion: ObserverCompletionOnce, manager: any AutomaticWorkoutBackgroundTaskManaging) {
        self.completion = completion
        self.manager = manager
    }

    func start(task: Task<Void, Never>, timeoutNanoseconds: UInt64) {
        self.task = task
        completionMonitor = Task { [weak self] in
            await task.value
            self?.finish()
        }
        deadlineTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: timeoutNanoseconds) }
            catch { return }
            self?.task?.cancel()
            self?.finish()
        }
        let identifier = manager.begin { [weak self] in
            Task { @MainActor in
                self?.task?.cancel()
                self?.finish()
            }
        }
        if finished {
            if identifier != .invalid { manager.end(identifier) }
            task.cancel()
            return
        }
        backgroundID = identifier
        if identifier == .invalid {
            task.cancel()
            finish()
        }
    }

    func waitUntilFinished() async {
        if finished { return }
        await withCheckedContinuation { continuation in
            if finished { continuation.resume() }
            else { waiters.append(continuation) }
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        completion.call()
        if backgroundID != .invalid { manager.end(backgroundID) }
        backgroundID = .invalid
        task = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        completionMonitor = nil
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

private final class ObserverCompletionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (() -> Void)?
    init(_ completion: @escaping () -> Void) { self.completion = completion }
    func call() {
        lock.lock()
        let value = completion
        completion = nil
        lock.unlock()
        value?()
    }
}
