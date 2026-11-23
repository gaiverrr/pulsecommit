import XCTest
import HealthKit
@testable import PulseCommit

final class HealthStoreClientTests: XCTestCase {
    func test_readTypesIncludeRespiratoryRateAndSleep() {
        let types = HealthAuthorizationView.readTypes()
        XCTAssertTrue(types.contains(HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!))
        XCTAssertTrue(types.contains(HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!))
        XCTAssertTrue(types.contains(HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!))
    }

    func test_isHealthDataAvailable_matchesHKHealthStore() {
        let client = HealthStoreClient()
        XCTAssertEqual(client.isHealthDataAvailable, HKHealthStore.isHealthDataAvailable())
    }

    func test_limitedHistoryLookupAvailabilityMatchesRuntime() {
        let client = HealthStoreClient()
        if #available(iOS 27.0, *) {
            XCTAssertTrue(client.supportsLimitedHistoryLookup)
        } else {
            XCTAssertFalse(client.supportsLimitedHistoryLookup)
        }
    }

    func test_historyCheckerRequestsEveryMultiTypeDependencyAndExcludesDisabledCategories() async throws {
        let provider = RecordingHistoryDateProvider(result: [:])
        let checker = HealthHistoryCoverageChecker(
            provider: provider,
            timezone: TimeZone(identifier: "UTC")!
        )

        try await checker.validate(
            from: Date(timeIntervalSince1970: 1_700_000_000),
            to: Date(timeIntervalSince1970: 1_700_086_400),
            enabledCategoryIds: ["activity_rings", "nutrition", "respiratory_rate", "workouts"]
        )

        let identifiers = await provider.requestedIdentifiers()
        XCTAssertEqual(identifiers, [
            HKQuantityTypeIdentifier.appleExerciseTime.rawValue,
            HKQuantityTypeIdentifier.appleStandTime.rawValue,
            HKQuantityTypeIdentifier.dietaryCaffeine.rawValue,
            HKQuantityTypeIdentifier.dietaryCarbohydrates.rawValue,
            HKQuantityTypeIdentifier.dietaryEnergyConsumed.rawValue,
            HKQuantityTypeIdentifier.dietaryFatTotal.rawValue,
            HKQuantityTypeIdentifier.dietaryFiber.rawValue,
            HKQuantityTypeIdentifier.dietaryProtein.rawValue,
            HKQuantityTypeIdentifier.dietarySugar.rawValue,
            HKQuantityTypeIdentifier.dietaryWater.rawValue,
            HKQuantityTypeIdentifier.heartRate.rawValue,
            HKQuantityTypeIdentifier.respiratoryRate.rawValue,
            HKCategoryTypeIdentifier.sleepAnalysis.rawValue,
            HKSeriesType.workoutRoute().identifier,
            HKObjectType.workoutType().identifier,
        ].sorted())
        XCTAssertFalse(identifiers.contains(HKQuantityTypeIdentifier.stepCount.rawValue))
    }

    func test_historyCheckerAcceptsEqualBoundaryAndOmittedTypesButRejectsOneSecondLater() async throws {
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let steps = HKQuantityType.quantityType(forIdentifier: .stepCount)!

        let equal = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: [steps: from]),
            timezone: TimeZone(identifier: "UTC")!
        )
        try await equal.validate(from: from, to: from.addingTimeInterval(86_400), enabledCategoryIds: ["steps"])

        let omitted = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: [:]),
            timezone: TimeZone(identifier: "UTC")!
        )
        try await omitted.validate(from: from, to: from.addingTimeInterval(86_400), enabledCategoryIds: ["steps"])

        let later = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: [steps: from.addingTimeInterval(1)]),
            timezone: TimeZone(identifier: "UTC")!
        )
        await XCTAssertThrowsErrorAsync(
            try await later.validate(from: from, to: from.addingTimeInterval(86_400), enabledCategoryIds: ["steps"])
        ) { error in
            XCTAssertEqual(error as? HealthHistoryCoverageError, .limitedHistory)
        }

        let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let mixed = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: [heartRate: from.addingTimeInterval(1)]),
            timezone: TimeZone(identifier: "UTC")!
        )
        await XCTAssertThrowsErrorAsync(
            try await mixed.validate(
                from: from,
                to: from.addingTimeInterval(86_400),
                enabledCategoryIds: ["steps", "heart_rate"]
            )
        ) { error in
            XCTAssertEqual(error as? HealthHistoryCoverageError, .limitedHistory)
        }
    }

    func test_historyCheckerIncludesSleepAndWristLookbacksUsingExportTimezone() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let from = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20, hour: 15))!
        let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let wrist = HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!
        let sleepStart = from.addingTimeInterval(-86_400)
        let wristStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: from))!

        let equal = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: [sleep: sleepStart, wrist: wristStart]),
            timezone: calendar.timeZone
        )
        try await equal.validate(
            from: from,
            to: from.addingTimeInterval(86_400),
            enabledCategoryIds: ["sleep", "wrist_temperature"]
        )

        let insideLookback = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: [sleep: sleepStart.addingTimeInterval(1), wrist: wristStart]),
            timezone: calendar.timeZone
        )
        await XCTAssertThrowsErrorAsync(
            try await insideLookback.validate(
                from: from,
                to: from.addingTimeInterval(86_400),
                enabledCategoryIds: ["sleep", "wrist_temperature"]
            )
        ) { error in
            XCTAssertEqual(error as? HealthHistoryCoverageError, .limitedHistory)
        }
    }

    func test_historyCheckerPassesLegacyAndMapsNativeFailureToGenericCheckFailure() async throws {
        let from = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(result: nil),
            timezone: TimeZone(identifier: "UTC")!
        )
        try await legacy.validate(
            from: from,
            to: from.addingTimeInterval(86_400),
            enabledCategoryIds: ["future_category_without_a_plan"]
        )

        let failing = HealthHistoryCoverageChecker(
            provider: RecordingHistoryDateProvider(error: ProviderFailure()),
            timezone: TimeZone(identifier: "UTC")!
        )
        await XCTAssertThrowsErrorAsync(
            try await failing.validate(from: from, to: from.addingTimeInterval(86_400), enabledCategoryIds: ["steps"])
        ) { error in
            XCTAssertEqual(error as? HealthHistoryCoverageError, .checkFailed)
        }
    }
}

private struct ProviderFailure: Error {}

private actor RecordingHistoryDateProvider: HealthHistoryDateProviding {
    nonisolated let supportsLimitedHistoryLookup: Bool
    private let result: [HKObjectType: Date]?
    private let error: Error?
    private var identifiers: [String] = []

    init(result: [HKObjectType: Date]?) {
        self.supportsLimitedHistoryLookup = result != nil
        self.result = result
        self.error = nil
    }

    init(error: Error) {
        self.supportsLimitedHistoryLookup = true
        self.result = nil
        self.error = error
    }

    func earliestAuthorizedSampleDates(for types: Set<HKObjectType>) async throws -> [HKObjectType: Date]? {
        identifiers = types.map(\.identifier).sorted()
        if let error { throw error }
        return result
    }

    func requestedIdentifiers() -> [String] { identifiers }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
