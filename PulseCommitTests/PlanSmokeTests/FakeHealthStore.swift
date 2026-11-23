import Foundation
import HealthKit
@testable import PulseCommit

final class FakeHealthStore: HealthStoreAuthorizing, @unchecked Sendable {
    var isHealthDataAvailable: Bool { true }
    func requestAuthorization(toShare: Set<HKSampleType>?, read: Set<HKObjectType>?) async throws {}
    func execute(_ query: HKQuery) {}
    func stop(_ query: HKQuery) {}
    func cumulativeSum(of quantityType: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double? { nil }
}
