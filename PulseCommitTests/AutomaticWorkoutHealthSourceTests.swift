import HealthKit
import XCTest
@testable import PulseCommit

final class AutomaticWorkoutHealthSourceTests: XCTestCase {
    func test_limitedHistoryPreflightRequestsOnlyWorkoutAndFailsBeforeQuery() async {
        let from = Date(timeIntervalSince1970: 1_800_000_000)
        let provider = RecordingWorkoutHistoryProvider(
            result: [.workoutType(): from.addingTimeInterval(1)]
        )
        let store = HangingWorkoutHealthStore()
        let source = AutomaticWorkoutHealthSource(store: store, historyProvider: provider)

        do {
            _ = try await source.workouts(from: from, to: from.addingTimeInterval(100))
            XCTFail("Expected limited workout history")
        } catch {
            XCTAssertEqual(error as? HealthHistoryCoverageError, .limitedHistory)
        }

        let identifiers = await provider.requestedIdentifiers()
        XCTAssertEqual(identifiers, [HKObjectType.workoutType().identifier])
        XCTAssertEqual(store.executeCount, 0)
    }

    func test_hangingQueryTimesOutAndStopsHealthKitQuery() async {
        let provider = RecordingWorkoutHistoryProvider(result: nil, supportsLookup: false)
        let store = HangingWorkoutHealthStore()
        let source = AutomaticWorkoutHealthSource(
            store: store,
            historyProvider: provider,
            queryTimeoutNanoseconds: 1_000_000
        )

        do {
            _ = try await source.workouts(from: Date(), to: Date().addingTimeInterval(10))
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AutomaticWorkoutHealthSourceError, .timedOut)
        }

        XCTAssertEqual(store.executeCount, 1)
        XCTAssertEqual(store.stopCount, 1)
    }

    func test_historyPreflightSharesTheWholeOperationTimeout() async {
        let provider = SlowWorkoutHistoryProvider(delayNanoseconds: 100_000_000)
        let store = HangingWorkoutHealthStore()
        let source = AutomaticWorkoutHealthSource(
            store: store,
            historyProvider: provider,
            queryTimeoutNanoseconds: 5_000_000
        )
        let started = ContinuousClock.now

        do {
            _ = try await source.workouts(from: Date(), to: Date().addingTimeInterval(10))
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AutomaticWorkoutHealthSourceError, .timedOut)
        }

        XCTAssertLessThan(started.duration(to: .now), .milliseconds(80))
        XCTAssertEqual(store.executeCount, 0)
    }
}

private actor SlowWorkoutHistoryProvider: HealthHistoryDateProviding {
    nonisolated let supportsLimitedHistoryLookup = true
    let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64) { self.delayNanoseconds = delayNanoseconds }

    func earliestAuthorizedSampleDates(for types: Set<HKObjectType>) async throws -> [HKObjectType: Date]? {
        try await Task.sleep(nanoseconds: delayNanoseconds)
        return nil
    }
}

private actor RecordingWorkoutHistoryProvider: HealthHistoryDateProviding {
    nonisolated let supportsLimitedHistoryLookup: Bool
    private let result: [HKObjectType: Date]?
    private var identifiers: [String] = []

    init(result: [HKObjectType: Date]?, supportsLookup: Bool = true) {
        self.result = result
        self.supportsLimitedHistoryLookup = supportsLookup
    }

    func earliestAuthorizedSampleDates(for types: Set<HKObjectType>) async throws -> [HKObjectType: Date]? {
        identifiers = types.map(\.identifier).sorted()
        return result
    }

    func requestedIdentifiers() -> [String] { identifiers }
}

private final class HangingWorkoutHealthStore: HealthStoreAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var executions = 0
    private var stops = 0

    var isHealthDataAvailable: Bool { true }
    var executeCount: Int { lock.lock(); defer { lock.unlock() }; return executions }
    var stopCount: Int { lock.lock(); defer { lock.unlock() }; return stops }

    func requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?) async throws {}
    func execute(_ query: HKQuery) { lock.lock(); executions += 1; lock.unlock() }
    func stop(_ query: HKQuery) { lock.lock(); stops += 1; lock.unlock() }
    func cumulativeSum(of quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double? { nil }
}
