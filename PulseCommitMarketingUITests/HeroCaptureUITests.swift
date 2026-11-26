import XCTest

final class HeroCaptureUITests: XCTestCase {
    private var frames: [String: [String: [[Double]]]] = [:]

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func test_captureHeroScreens() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-marketingDemo", "-onboarding_completed", "YES"]
        app.launch()

        let exportButton = app.buttons["home.bigButton.topZone"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 20))
        pause(2)
        capture("01-home-idle", in: app)

        exportButton.tap()
        pause(0.5)
        capture("02-home-running-a", in: app)
        pause(1.2)
        capture("03-home-running-b", in: app)
        pause(1.6)
        capture("04-home-running-c", in: app)
        let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: exportButton)
        XCTAssertEqual(XCTWaiter().wait(for: [finished], timeout: 30), .completed)
        pause(1.5)
        capture("05-home-done", in: app)

        app.tabBars.buttons["History"].tap()
        pause(1.5)
        capture("06-history", in: app)

        let json = try JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: json, uniformTypeIdentifier: "public.json")
        attachment.name = "frames"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func pause(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let scale = Double(screenshot.image.size.width * screenshot.image.scale) / Double(app.frame.width)
        frames[name] = elementFrames(in: app, scale: scale)
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func elementFrames(in app: XCUIApplication, scale: Double) -> [String: [[Double]]] {
        let queries: [String: XCUIElementQuery] = [
            "topZone": app.buttons.matching(identifier: "home.bigButton.topZone"),
            "chipRow": app.descendants(matching: .any).matching(identifier: "home.bigButton.chipRow"),
            "commitRows": app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "^[0-9a-f]{7}$")),
            "historyTab": app.tabBars.buttons.matching(identifier: "History"),
        ]
        var result: [String: [[Double]]] = [:]
        for (key, query) in queries {
            result[key] = query.allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
                .map { element in
                    let frame = element.frame
                    return [frame.minX, frame.minY, frame.width, frame.height].map { ($0 * scale).rounded() }
                }
        }
        return result
    }
}
