import XCTest

final class ScreenshotsPlanTests: XCTestCase {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        let url = repoRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func test_screenshotsPlan_keepsUncapturedAssetsPendingWithinAppleCount() throws {
        let body = try read("docs/store/screenshots-plan.md")
        XCTAssertTrue(body.contains("one to 10"), "Apple permits one to 10 screenshots")
        XCTAssertTrue(body.contains("all final App Store screenshots are pending"),
                      "uncaptured screenshots must remain explicitly pending")
    }

    func test_screenshotsPlan_usesHighestResolutionSetWithoutRequiringTwoSets() throws {
        let body = try read("docs/store/screenshots-plan.md")
        XCTAssertTrue(body.contains("1320 × 2868"),
                      "must document iPhone 6.9\" 1320×2868 px spec")
        XCTAssertTrue(body.contains("6.5-inch set is required only when 6.9-inch screenshots are not provided"))
        XCTAssertFalse(body.contains("Total: 12 PNGs"), "a second mandatory screenshot set is obsolete")
        XCTAssertTrue(body.contains("no alpha"), "Apple rejects alpha/transparency")
    }

    func test_screenshotsPlan_documentsCaptureProcedure() throws {
        let body = try read("docs/store/screenshots-plan.md")
        XCTAssertTrue(body.contains("xcrun simctl io <UDID> screenshot"),
                      "capture must target the selected simulator rather than any booted device")
        XCTAssertTrue(body.contains("PulseCommit.xcodeproj` is missing or `project.yml` changed"),
                      "a clean checkout must generate the Xcode project before capture")
        XCTAssertFalse(body.contains("paste the caption"),
                       "App Store Connect has no per-screenshot Caption field")
        XCTAssertFalse(body.contains("sandbox PAT"),
                       "the app uses GitHub OAuth Device Flow, not PAT screenshot setup")
    }
}
