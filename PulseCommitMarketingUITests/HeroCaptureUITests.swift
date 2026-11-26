import XCTest

final class HeroCaptureUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func test_captureHeroScreens() {
        let app = XCUIApplication()
        app.launchArguments = ["-marketingDemo", "-onboarding_completed", "YES"]
        app.launch()

        let exportButton = app.buttons["home.bigButton.topZone"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 20))
        pause(2)
        capture("01-home-idle")

        exportButton.tap()
        pause(0.5)
        capture("02-home-running-a")
        pause(1.2)
        capture("03-home-running-b")
        pause(1.6)
        capture("04-home-running-c")
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: exportButton)
        XCTAssertEqual(XCTWaiter().wait(for: [finished], timeout: 30), .completed)
        pause(1.5)
        capture("05-home-done")

        app.tabBars.buttons["History"].tap()
        pause(1.5)
        capture("06-history")
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
