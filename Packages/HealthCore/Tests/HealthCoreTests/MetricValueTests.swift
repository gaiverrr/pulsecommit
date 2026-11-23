import XCTest
@testable import HealthCore

final class MetricValueTests: XCTestCase {
    func test_intVariant_roundTrips() throws {
        let original = MetricValue.int(12483)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), "12483")
        let decoded = try JSONDecoder().decode(MetricValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_doubleVariant_roundTrips() throws {
        let original = MetricValue.double(48.2)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MetricValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_stringVariant_roundTrips() throws {
        let original = MetricValue.string("ml/kg/min")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"ml\\/kg\\/min\"")
        let decoded = try JSONDecoder().decode(MetricValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_decoding_failsOnUnsupportedType() {
        let json = "true".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(MetricValue.self, from: json))
    }

    func test_decoding_failsOnNullValue() {
        let json = "null".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(MetricValue.self, from: json))
    }
}
