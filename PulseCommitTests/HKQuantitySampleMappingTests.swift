import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class HKQuantitySampleMappingTests: XCTestCase {
    func test_map_stepCountSample_producesExpectedDTO() {
        let type = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let unit = HKUnit.count()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(60)
        let quantity = HKQuantity(unit: unit, doubleValue: 1234)
        let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end)

        let dto = HKQuantitySampleMapping.map(sample, categoryID: "steps", unit: unit)

        XCTAssertEqual(dto.categoryID, "steps")
        XCTAssertEqual(dto.startDate, start)
        XCTAssertEqual(dto.endDate, end)
        XCTAssertEqual(dto.value, 1234)
        XCTAssertEqual(dto.unit, unit.unitString)
    }
}
