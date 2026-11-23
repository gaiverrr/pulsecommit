import Foundation
import HealthKit

protocol HealthHistoryDateProviding: Sendable {
    var supportsLimitedHistoryLookup: Bool { get }

    /// `nil` means this OS predates the native limited-history lookup. An empty
    /// dictionary means iOS 27 found no positively limited types; omitted types
    /// remain intentionally ambiguous between full and denied read access.
    func earliestAuthorizedSampleDates(
        for types: Set<HKObjectType>
    ) async throws -> [HKObjectType: Date]?
}

enum HealthHistoryCoverageError: Error, Equatable, Sendable {
    case limitedHistory
    case checkFailed

    var userMessage: String {
        switch self {
        case .limitedHistory:
            return "Health history is incomplete for an enabled category. Choose a fully covered range, allow Full History in Health settings, or disable affected optional categories."
        case .checkFailed:
            return "Health history access couldn’t be verified. Try again, choose a fully covered range, allow Full History in Health settings, or disable affected optional categories."
        }
    }
}

struct HealthHistoryCoverageChecker: Sendable {
    private let provider: any HealthHistoryDateProviding
    private let calendar: Calendar

    init(provider: any HealthHistoryDateProviding, timezone: TimeZone) {
        self.provider = provider
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        self.calendar = calendar
    }

    func validate(
        from: Date,
        to: Date,
        enabledCategoryIds: Set<String>
    ) async throws {
        _ = to
        guard provider.supportsLimitedHistoryLookup else { return }
        let requiredStarts: [HKObjectType: Date]
        do {
            requiredStarts = try requirements(from: from, enabledCategoryIds: enabledCategoryIds)
        } catch {
            throw HealthHistoryCoverageError.checkFailed
        }

        let boundaries: [HKObjectType: Date]?
        do {
            boundaries = try await provider.earliestAuthorizedSampleDates(
                for: Set(requiredStarts.keys)
            )
        } catch {
            throw HealthHistoryCoverageError.checkFailed
        }

        guard let boundaries else { return }
        for (type, boundary) in boundaries {
            guard let requiredStart = requiredStarts[type] else { continue }
            if boundary > requiredStart {
                throw HealthHistoryCoverageError.limitedHistory
            }
        }
    }

    private func requirements(
        from: Date,
        enabledCategoryIds: Set<String>
    ) throws -> [HKObjectType: Date] {
        var result: [HKObjectType: Date] = [:]

        func add(_ type: HKObjectType, from requiredStart: Date) {
            if let existing = result[type] {
                result[type] = min(existing, requiredStart)
            } else {
                result[type] = requiredStart
            }
        }

        for categoryID in enabledCategoryIds {
            switch categoryID {
            case "steps":
                add(HKQuantityType.quantityType(forIdentifier: .stepCount)!, from: from)
            case "distance_walking_running":
                add(HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!, from: from)
            case "heart_rate":
                add(HKQuantityType.quantityType(forIdentifier: .heartRate)!, from: from)
            case "resting_heart_rate":
                add(HKQuantityType.quantityType(forIdentifier: .restingHeartRate)!, from: from)
            case "hrv_sdnn":
                add(HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!, from: from)
            case "vo2_max":
                add(HKQuantityType.quantityType(forIdentifier: .vo2Max)!, from: from)
            case "active_energy":
                add(HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!, from: from)
            case "activity_rings":
                add(HKQuantityType.quantityType(forIdentifier: .appleStandTime)!, from: from)
                add(HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!, from: from)
            case "sleep":
                add(
                    HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
                    from: from.addingTimeInterval(-86_400)
                )
            case "respiratory_rate":
                let requiredStart = from.addingTimeInterval(-86_400)
                add(HKQuantityType.quantityType(forIdentifier: .respiratoryRate)!, from: requiredStart)
                add(HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!, from: requiredStart)
            case "wrist_temperature":
                guard let requiredStart = calendar.date(
                    byAdding: .day,
                    value: -29,
                    to: calendar.startOfDay(for: from)
                ) else {
                    throw HealthHistoryCoverageError.checkFailed
                }
                add(
                    HKQuantityType.quantityType(forIdentifier: .appleSleepingWristTemperature)!,
                    from: requiredStart
                )
            case "workouts":
                add(HKObjectType.workoutType(), from: from)
                add(HKSeriesType.workoutRoute(), from: from)
                add(HKQuantityType.quantityType(forIdentifier: .heartRate)!, from: from)
            case "body_mass":
                add(HKQuantityType.quantityType(forIdentifier: .bodyMass)!, from: from)
            case "state_of_mind":
                if #available(iOS 18.0, *) {
                    add(HKObjectType.stateOfMindType(), from: from)
                }
            case "nutrition":
                for subtype in NutritionCategory.subtypes {
                    add(HKQuantityType.quantityType(forIdentifier: subtype.identifier)!, from: from)
                }
            default:
                throw HealthHistoryCoverageError.checkFailed
            }
        }

        return result
    }
}

public final class HealthStoreClient: HealthStoreAuthorizing, HealthHistoryDateProviding, @unchecked Sendable {
    private let store: HKHealthStore

    public init() {
        self.store = HKHealthStore()
    }

    public var isHealthDataAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    public func requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?) async throws {
        try await store.requestAuthorization(toShare: toShare ?? [], read: read ?? [])
    }

    public func execute(_ query: HKQuery) {
        store.execute(query)
    }

    public func stop(_ query: HKQuery) {
        store.stop(query)
    }

    func enableWorkoutBackgroundDelivery(
        completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate, withCompletion: completion)
    }

    func disableWorkoutBackgroundDelivery(
        completion: @escaping @Sendable (Bool, Error?) -> Void
    ) {
        store.disableBackgroundDelivery(for: .workoutType(), withCompletion: completion)
    }

    var supportsLimitedHistoryLookup: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    func earliestAuthorizedSampleDates(
        for types: Set<HKObjectType>
    ) async throws -> [HKObjectType: Date]? {
        guard #available(iOS 27.0, *) else { return nil }
        return try await store.earliestAuthorizedSampleDate(for: types)
    }

    public func cumulativeSum(
        of quantityType: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit
    ) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            self.store.execute(query)
        }
    }
}
