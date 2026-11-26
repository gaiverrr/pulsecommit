import XCTest

final class StoreCaptureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func test_captureStoreScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-marketingDemo", "-onboarding_completed", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["home.bigButton.topZone"].waitForExistence(timeout: 20))
        pause(2)
        capture("store-home")

        app.tabBars.buttons["History"].tap()
        pause(1.5)
        capture("store-history")

        app.tabBars.buttons["Destinations"].tap()
        XCTAssertTrue(app.staticTexts["agent.example.net"].waitForExistence(timeout: 10))
        pause(1.5)
        capture("store-destinations")

        app.staticTexts["agent.example.net"].tap()
        let endpoint = app.textFields["webhook.endpoint"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 10))
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS 'agent.example.net'"), object: endpoint)
        XCTAssertEqual(XCTWaiter().wait(for: [loaded], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["webhook.token"].isHittable)
        pause(1.5)
        capture("store-webhook")

        app.tabBars.buttons["Settings"].tap()
        let schedule = app.staticTexts["Schedule via"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        schedule.tap()
        XCTAssertTrue(app.navigationBars["Automate"].waitForExistence(timeout: 10))
        pause(1.5)
        capture("store-automate")
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
