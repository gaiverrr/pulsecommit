import XCTest
@testable import PulseCommit

final class BuildIdentityTests: XCTestCase {
    func test_gitSHA_isNonEmpty() {
        XCTAssertFalse(BuildIdentity.gitSHA.isEmpty)
    }

    func test_commitDate_isNonEmpty() {
        XCTAssertFalse(BuildIdentity.commitDate.isEmpty)
    }

    func test_homeSupertitle_includesShaAndDate() {
        let s = HomeView.buildIdentitySupertitle(
            appVersion: "1.0",
            deviceName: "iPhone",
            timezoneAbbreviation: "WEST",
            gitSHA: "abc1234",
            commitDate: "2026-05-16"
        )
        XCTAssertTrue(s.contains("abc1234"), "supertitle missing SHA: \(s)")
        XCTAssertTrue(s.contains("2026-05-16"), "supertitle missing date: \(s)")
        XCTAssertTrue(s.contains("v1.0"))
        XCTAssertTrue(s.contains("iPhone"))
        XCTAssertTrue(s.contains("WEST"))
    }

    func test_homeSupertitle_usesRealBuildIdentityByDefault() {
        let s = HomeView.buildIdentitySupertitle(
            appVersion: "1.0",
            deviceName: "iPhone",
            timezoneAbbreviation: "WEST"
        )
        XCTAssertTrue(s.contains(BuildIdentity.gitSHA))
        XCTAssertTrue(s.contains(BuildIdentity.commitDate))
    }
}
