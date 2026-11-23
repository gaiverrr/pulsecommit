import Foundation
import HealthKit

public protocol HealthStoreAuthorizing: AnyObject, Sendable {
    var isHealthDataAvailable: Bool { get }
    func requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?) async throws
    func execute(_ query: HKQuery)
    func stop(_ query: HKQuery)

    /// HealthKit-native cross-source deduplicated cumulative sum.
    /// When the user wears Apple Watch and carries iPhone, both record stepCount,
    /// activeEnergyBurned, etc. A naive `HKSampleQuery` then `.reduce(+)` doubles the total.
    /// `HKStatisticsQuery(options: .cumulativeSum)` picks the canonical source per overlap.
    /// Returns the summed quantity in `unit`, or `nil` if no samples in range.
    func cumulativeSum(
        of quantityType: HKQuantityType,
        predicate: NSPredicate,
        unit: HKUnit
    ) async throws -> Double?
}
