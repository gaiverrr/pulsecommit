import XCTest
import HealthKit
@testable import PulseCommit

@MainActor
final class AutomaticWorkoutObserverControllerTests: XCTestCase {
    func test_launchRegistersSynchronouslyOnlyWhenOptedInAndDisableStopsWorkoutObserver() {
        let suite = "AutomaticWorkoutObserverControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = PreferencesStore(defaults: defaults)
        let store = RecordingObserverHealthStore()
        let controller = AutomaticWorkoutObserverController(
            store: store,
            preferences: preferences,
            reconcileAction: {}
        )

        controller.registerSynchronouslyIfOptedIn()
        XCTAssertEqual(store.executeCount, 0)

        preferences.automaticWorkoutTelegramEnabled = true
        controller.registerSynchronouslyIfOptedIn()
        XCTAssertEqual(store.executeCount, 1)
        XCTAssertEqual(store.enableCount, 1)

        preferences.automaticWorkoutTelegramEnabled = false
        controller.refreshRegistration()
        XCTAssertEqual(store.stopCount, 1)
        XCTAssertEqual(store.disableCount, 1)
    }

    func test_observerErrorCompletesOnceWithoutStartingReconciliation() async {
        let preferences = makePreferences(enabled: true)
        let store = RecordingObserverHealthStore()
        let capture = ObserverHandlerCapture()
        let backgroundTasks = RecordingBackgroundTaskManager()
        let reconciliations = LockedCounter()
        let controller = AutomaticWorkoutObserverController(
            store: store,
            preferences: preferences,
            reconcileAction: { reconciliations.increment() },
            observerFactory: capture.factory,
            backgroundTasks: backgroundTasks,
            protectedDataAvailable: { true }
        )
        controller.registerSynchronouslyIfOptedIn()
        let completion = expectation(description: "observer completion")

        capture.fire(error: NSError(domain: "HealthKit", code: 1)) { completion.fulfill() }
        await fulfillment(of: [completion], timeout: 1)

        XCTAssertEqual(reconciliations.value, 0)
        XCTAssertEqual(backgroundTasks.beginCount, 0)
    }

    func test_backgroundExpirationCompletesExactlyOnceAndCancelsCallbackWork() async {
        let preferences = makePreferences(enabled: true)
        let store = RecordingObserverHealthStore()
        let capture = ObserverHandlerCapture()
        let backgroundTasks = RecordingBackgroundTaskManager()
        let gate = SuspendedObserverReconciliation()
        let controller = AutomaticWorkoutObserverController(
            store: store,
            preferences: preferences,
            reconcileAction: { await gate.run() },
            observerFactory: capture.factory,
            backgroundTasks: backgroundTasks,
            protectedDataAvailable: { true }
        )
        controller.registerSynchronouslyIfOptedIn()
        let completion = expectation(description: "observer completion")
        completion.expectedFulfillmentCount = 1

        capture.fire(error: nil) { completion.fulfill() }
        await gate.waitUntilStarted()
        backgroundTasks.expire()
        await fulfillment(of: [completion], timeout: 1)
        await gate.release()
        await Task.yield()

        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertEqual(backgroundTasks.endCount, 1)
        let cancelled = await gate.wasCancelled()
        XCTAssertTrue(cancelled)
    }

    func test_invalidBackgroundTaskCompletesPromptlyAndCancelsCallbackWork() async {
        let preferences = makePreferences(enabled: true)
        let capture = ObserverHandlerCapture()
        let backgroundTasks = RecordingBackgroundTaskManager(identifier: .invalid)
        let gate = SuspendedObserverReconciliation()
        let controller = AutomaticWorkoutObserverController(
            store: RecordingObserverHealthStore(),
            preferences: preferences,
            reconcileAction: { await gate.run() },
            observerFactory: capture.factory,
            backgroundTasks: backgroundTasks,
            protectedDataAvailable: { true }
        )
        controller.registerSynchronouslyIfOptedIn()
        let completion = expectation(description: "observer completion")
        completion.expectedFulfillmentCount = 1

        capture.fire(error: nil) { completion.fulfill() }
        await fulfillment(of: [completion], timeout: 0.5)
        await gate.release()
        await Task.yield()

        XCTAssertEqual(backgroundTasks.beginCount, 1)
        XCTAssertEqual(backgroundTasks.endCount, 0)
        let invalidCancelled = await gate.wasCancelled()
        XCTAssertTrue(invalidCancelled)
    }

    func test_observerPassDeadlineCompletesWithoutUIApplicationExpiration() async {
        let preferences = makePreferences(enabled: true)
        let capture = ObserverHandlerCapture()
        let gate = SuspendedObserverReconciliation()
        let controller = AutomaticWorkoutObserverController(
            store: RecordingObserverHealthStore(),
            preferences: preferences,
            reconcileAction: { await gate.run() },
            observerFactory: capture.factory,
            backgroundTasks: RecordingBackgroundTaskManager(),
            protectedDataAvailable: { true },
            callbackTimeoutNanoseconds: 20_000_000
        )
        controller.registerSynchronouslyIfOptedIn()
        let completion = expectation(description: "observer completion")
        completion.expectedFulfillmentCount = 1

        capture.fire(error: nil) { completion.fulfill() }
        await fulfillment(of: [completion], timeout: 0.5)
        await gate.release()
        await Task.yield()

        let deadlineCancelled = await gate.wasCancelled()
        XCTAssertTrue(deadlineCancelled)
    }

    func test_topicCategoryMasterAndResetInvalidationsImmediatelyStopRegistration() async {
        let preferences = makePreferences(enabled: false)
        preferences.enabledCategoryIds = ["workouts"]
        let store = RecordingObserverHealthStore()
        let controller = AutomaticWorkoutObserverController(
            store: store,
            preferences: preferences,
            reconcileAction: {},
            protectedDataAvailable: { true }
        )
        preferences.bindAutomaticWorkoutConfigurationChanged { [weak controller] in
            Task { @MainActor in controller?.refreshRegistration() }
        }

        preferences.automaticWorkoutTelegramEnabled = true
        await settleMainActorTasks()
        XCTAssertEqual(store.executeCount, 1)
        preferences.telegramThreadId = 7
        await settleMainActorTasks()
        XCTAssertEqual(store.stopCount, 1)

        preferences.automaticWorkoutTelegramEnabled = true
        await settleMainActorTasks()
        XCTAssertEqual(store.executeCount, 2)
        preferences.enabledCategoryIds = ["steps"]
        await settleMainActorTasks()
        XCTAssertEqual(store.stopCount, 2)

        preferences.enabledCategoryIds = ["workouts"]
        preferences.automaticWorkoutTelegramEnabled = true
        await settleMainActorTasks()
        XCTAssertEqual(store.executeCount, 3)
        preferences.telegramExportEnabled = false
        await settleMainActorTasks()
        XCTAssertEqual(store.stopCount, 3)

        preferences.telegramExportEnabled = true
        preferences.automaticWorkoutTelegramEnabled = true
        await settleMainActorTasks()
        XCTAssertEqual(store.executeCount, 4)
        preferences.reset()
        await settleMainActorTasks()
        XCTAssertEqual(store.stopCount, 4)
    }

    private func makePreferences(enabled: Bool) -> PreferencesStore {
        let suite = "AutomaticWorkoutObserverControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = PreferencesStore(defaults: defaults)
        preferences.automaticWorkoutTelegramEnabled = enabled
        return preferences
    }

    private func settleMainActorTasks() async {
        for _ in 0..<4 { await Task.yield() }
    }
}

@MainActor
private final class ObserverHandlerCapture {
    private var handler: AutomaticWorkoutObserverUpdateHandler?

    var factory: AutomaticWorkoutObserverFactory {
        { [weak self] handler in
            self?.handler = handler
            return HKObserverQuery(sampleType: .workoutType(), predicate: nil) { _, completion, error in
                handler(error, completion)
            }
        }
    }

    func fire(error: Error?, completion: @escaping () -> Void) {
        handler?(error, completion)
    }
}

@MainActor
private final class RecordingBackgroundTaskManager: AutomaticWorkoutBackgroundTaskManaging {
    private var expiration: (@Sendable () -> Void)?
    private(set) var beginCount = 0
    private(set) var endCount = 0

    private let identifier: UIBackgroundTaskIdentifier

    init(identifier: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier(rawValue: 1)) {
        self.identifier = identifier
    }

    func begin(expiration: @escaping @Sendable () -> Void) -> UIBackgroundTaskIdentifier {
        beginCount += 1
        self.expiration = expiration
        return identifier
    }

    func end(_ identifier: UIBackgroundTaskIdentifier) { endCount += 1 }
    func expire() { expiration?(); expiration = nil }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

private actor SuspendedObserverReconciliation {
    private var started = false
    private var cancelled = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func run() async {
        started = true
        startWaiter?.resume()
        startWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
        cancelled = Task.isCancelled
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func release() { releaseWaiter?.resume(); releaseWaiter = nil }
    func wasCancelled() -> Bool { cancelled }
}

private final class RecordingObserverHealthStore: AutomaticWorkoutObserverHealthStore, @unchecked Sendable {
    private(set) var executeCount = 0
    private(set) var stopCount = 0
    private(set) var enableCount = 0
    private(set) var disableCount = 0

    func execute(_ query: HKQuery) { executeCount += 1 }
    func stop(_ query: HKQuery) { stopCount += 1 }
    func enableWorkoutBackgroundDelivery(completion: @escaping @Sendable (Bool, Error?) -> Void) {
        enableCount += 1
        completion(true, nil)
    }
    func disableWorkoutBackgroundDelivery(completion: @escaping @Sendable (Bool, Error?) -> Void) {
        disableCount += 1
        completion(true, nil)
    }
}
