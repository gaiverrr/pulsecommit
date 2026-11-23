import XCTest
@testable import PulseCommit

@MainActor
final class HomeViewHeaderPillTests: XCTestCase {
    func test_headerPillText_reflectsPhase() {
        XCTAssertEqual(HomeView.headerPillText(for: .idle), "READY")
        XCTAssertEqual(HomeView.headerPillText(for: .done(at: Date())), "READY")
        XCTAssertEqual(HomeView.headerPillText(for: .running), "RUNNING")
        XCTAssertEqual(HomeView.headerPillText(for: .error(reason: "export failed")), "FAILED")
    }

    func test_headerPillIsError_onlyInErrorPhase() {
        XCTAssertFalse(HomeView.headerPillIsError(for: .idle))
        XCTAssertFalse(HomeView.headerPillIsError(for: .running))
        XCTAssertFalse(HomeView.headerPillIsError(for: .done(at: Date())))
        XCTAssertTrue(HomeView.headerPillIsError(for: .error(reason: "export failed")))
    }
}
