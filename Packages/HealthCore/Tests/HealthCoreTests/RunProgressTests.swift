import XCTest
@testable import HealthCore

final class RunProgressTests: XCTestCase {
    func test_readingSummary_equalForSameValues() {
        XCTAssertEqual(
            RunProgress.readingSummary(categoryID: "steps", completed: 3, total: 14),
            RunProgress.readingSummary(categoryID: "steps", completed: 3, total: 14)
        )
    }

    func test_readingSummary_notEqualToReadingSamples() {
        XCTAssertNotEqual(
            RunProgress.readingSummary(categoryID: "steps", completed: 3, total: 14),
            RunProgress.readingSamples(categoryID: "steps", completed: 3, total: 14)
        )
    }

    func test_startingSamplesFetch_equalToItself() {
        XCTAssertEqual(RunProgress.startingSamplesFetch, RunProgress.startingSamplesFetch)
    }

    func test_readingSamples_differentCompletedNotEqual() {
        XCTAssertNotEqual(
            RunProgress.readingSamples(categoryID: "steps", completed: 3, total: 14),
            RunProgress.readingSamples(categoryID: "steps", completed: 4, total: 14)
        )
    }

    func test_readingSummary_differentCategoryIDNotEqual() {
        XCTAssertNotEqual(
            RunProgress.readingSummary(categoryID: "steps", completed: 3, total: 14),
            RunProgress.readingSummary(categoryID: "heart_rate", completed: 3, total: 14)
        )
    }
}
