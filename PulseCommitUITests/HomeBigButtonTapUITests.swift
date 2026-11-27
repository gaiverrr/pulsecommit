import XCTest

final class HomeBigButtonTapUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(failing: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-marketingDemo", "-onboarding_completed", "YES"] + (failing ? ["-marketingDemoFailGitHub"] : [])
        app.launch()
        return app
    }

    @MainActor
    func test_idle_tapJustAboveDividerExports() {
        let app = launch(failing: false)
        let button = app.buttons["home.bigButton.topZone"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        let frame = button.frame
        let point = button.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.width / 2, dy: frame.height - 50))
        point.tap()
        let running = NSPredicate(format: "isEnabled == false")
        let expectation = XCTNSPredicateExpectation(predicate: running, object: button)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 10), .completed, "tap in the lower gap did not start an export")
    }

    @MainActor
    func test_error_tappingReasonOpensDetailSheet() {
        let app = launch(failing: true)
        let button = app.buttons["home.bigButton.topZone"]
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        button.tap()
        let details = app.buttons["home.bigButton.subLabel"]
        XCTAssertTrue(details.waitForExistence(timeout: 30), "details button never appeared after a failed run")
        details.tap()
        XCTAssertTrue(app.navigationBars["Run details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'demo github failure'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["home.bigButton.topZone"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Run details"].exists)
    }
}
