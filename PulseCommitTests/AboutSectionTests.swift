import XCTest
@testable import PulseCommit

final class AboutSectionTests: XCTestCase {
    func test_changelogStartsWithTheShippingVersion() {
        let marketing = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(ChangelogView.entries.first?.version, marketing)
        XCTAssertTrue(ChangelogView.entries.allSatisfy { !$0.items.isEmpty })
        XCTAssertEqual(Set(ChangelogView.entries.map(\.version)).count, ChangelogView.entries.count)
    }

    func test_aboutLinksPointAtPublicDestinations() {
        XCTAssertEqual(AboutLinks.website.absoluteString, "https://pulsecommit.app")
        XCTAssertEqual(AboutLinks.source.absoluteString, "https://github.com/gaiverrr/pulsecommit")
        XCTAssertEqual(AboutLinks.contact.absoluteString, "mailto:hi@pulsecommit.app")
        XCTAssertEqual(AboutLinks.releases.host, "github.com")
    }

    func test_versionLabelIncludesBuildWhenPresent() {
        XCTAssertEqual(SettingsView.versionLabel(marketing: "1.0.1", build: "8"), "1.0.1 (8)")
        XCTAssertEqual(SettingsView.versionLabel(marketing: "1.0.1", build: ""), "1.0.1")
    }

    func test_licensesIncludeTheAppsOwnMITLicense() throws {
        let repoLicense = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("LICENSE"),
            encoding: .utf8
        )
        XCTAssertEqual(LicensesView.pulseCommitLicense.trimmingCharacters(in: .whitespacesAndNewlines),
                       repoLicense.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
