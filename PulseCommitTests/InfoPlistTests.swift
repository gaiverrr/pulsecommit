import XCTest
@testable import PulseCommit

final class InfoPlistTests: XCTestCase {
    private let expectedHealthUsage = "Pulse Commit reads Apple Health data you select for manual exports to your GitHub repository or Telegram chat. If you separately turn on finished-workout messages, it also reads recently saved workouts in the background and sends one text summary to the Telegram chat and optional topic you approve."

    private func hostInfoDictionary() -> [String: Any] {
        if let testHostPath = Bundle(for: type(of: self)).infoDictionary?["BUNDLE_LOADER"] as? String {
            let appBundleURL = URL(fileURLWithPath: testHostPath).deletingLastPathComponent()
            if let appBundle = Bundle(url: appBundleURL), let info = appBundle.infoDictionary {
                return info
            }
        }
        return Bundle.main.infoDictionary ?? [:]
    }

    func test_healthShareUsageDescription_matchesExplicitCopy() {
        let info = hostInfoDictionary()
        let value = info["NSHealthShareUsageDescription"] as? String
        XCTAssertEqual(value, expectedHealthUsage)
    }

    func test_healthShareUsageDescription_namesBothDestinations() {
        let info = hostInfoDictionary()
        let value = info["NSHealthShareUsageDescription"] as? String ?? ""
        XCTAssertTrue(value.contains("GitHub"))
        XCTAssertTrue(value.contains("Telegram"))
    }

    func test_healthUpdateUsageDescription_statesAppNeverWrites() {
        let info = hostInfoDictionary()
        let value = info["NSHealthUpdateUsageDescription"] as? String
        XCTAssertEqual(value, "Pulse Commit does not write to Apple Health. It only reads the data you select so you can export it to your GitHub repository or Telegram chat.")
    }

    func test_queriesSchemesDeclareShortcuts_soAddToShortcutsButtonWorks() {
        let info = hostInfoDictionary()
        let schemes = info["LSApplicationQueriesSchemes"] as? [String] ?? []
        XCTAssertTrue(
            schemes.contains("shortcuts"),
            "canOpenURL(\"shortcuts://\") returns false unless the scheme is declared, making Add to Shortcuts a silent no-op"
        )
    }

    func test_orientationLockedToPortrait() {
        let info = hostInfoDictionary()
        let orientations = info["UISupportedInterfaceOrientations"] as? [String] ?? []
        XCTAssertEqual(orientations, ["UIInterfaceOrientationPortrait"])
    }

    func test_exportComplianceDeclaredAsExempt() {
        let info = hostInfoDictionary()
        let value = info["ITSAppUsesNonExemptEncryption"] as? Bool
        XCTAssertEqual(value, false, "HTTPS-only app is exempt; declaring it skips the manual question on every upload")
    }

    func test_displayNameHasSpace() {
        let info = hostInfoDictionary()
        XCTAssertEqual(info["CFBundleDisplayName"] as? String, "Pulse Commit")
    }

    func test_appTargetIsiPhoneOnly() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        let pbxproj = try String(
            contentsOf: root.appendingPathComponent("PulseCommit.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertFalse(
            pbxproj.contains("TARGETED_DEVICE_FAMILY = \"1,2\""),
            "xcodegen writes a target-level 1,2 default that overrides the project-level setting, shipping an unintended iPad app"
        )
        XCTAssertTrue(pbxproj.contains("TARGETED_DEVICE_FAMILY = 1"))
    }
}
