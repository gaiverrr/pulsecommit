import XCTest
@testable import HealthCore

final class SchemaVersionTests: XCTestCase {
    func testCurrentIsOneDotZero() {
        XCTAssertEqual(SchemaVersion.current, "1.0")
    }
}
