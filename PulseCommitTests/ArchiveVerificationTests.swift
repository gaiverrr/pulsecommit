import XCTest

/// Verifies that a release-style archive of PulseCommit contains the launch-critical
/// privacy assets. Inspects a pre-built archive at `/tmp/PulseCommit.xcarchive` if
/// present, otherwise skips — iOS Simulator XCTests have no Process available, so
/// the archive must be built outside the test harness (see skip message).
final class ArchiveVerificationTests: XCTestCase {
    private let archivePath = "/tmp/PulseCommit.xcarchive"

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func ensureArchiveExists() throws {
        guard FileManager.default.fileExists(atPath: archivePath) else {
            throw XCTSkip("No archive at \(archivePath); run `xcodebuild archive -project PulseCommit.xcodeproj -scheme PulseCommit -archivePath /tmp/PulseCommit.xcarchive -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO` first.")
        }
    }

    func test_archive_containsPrivacyManifestInAppBundle() throws {
        try ensureArchiveExists()
        let path = "\(archivePath)/Products/Applications/PulseCommit.app/PrivacyInfo.xcprivacy"
        XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                      "PrivacyInfo.xcprivacy must be at the top of the app bundle, not nested")
    }

    func test_archive_infoPlistContainsNewHealthShareUsageString() throws {
        try ensureArchiveExists()
        let plistPath = "\(archivePath)/Products/Applications/PulseCommit.app/Info.plist"
        let url = URL(fileURLWithPath: plistPath)
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        let usage = plist?["NSHealthShareUsageDescription"] as? String
        XCTAssertEqual(
            usage,
            "Pulse Commit reads Apple Health data you select for manual exports. If you separately turn on finished-workout messages, it also reads recently saved workouts in the background and sends one text summary to the Telegram chat and optional topic you approve."
        )
    }

    func test_archive_containsNoExtensionPlugIns() throws {
        try ensureArchiveExists()
        let pluginsPath = "\(archivePath)/Products/Applications/PulseCommit.app/PlugIns"
        XCTAssertFalse(FileManager.default.fileExists(atPath: pluginsPath),
                       "v1.0 ships no app extensions; PlugIns/ in the bundle indicates an unintended target leaked in")
    }
}
