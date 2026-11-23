import XCTest
@testable import PulseCommit

final class PrivacyManifestTests: XCTestCase {
    private func loadManifest() throws -> [String: Any] {
        let bundle = Bundle(for: type(of: self))
        let hostBundle: Bundle = {
            guard let testHost = bundle.infoDictionary?["BUNDLE_LOADER"] as? String,
                  let url = URL(string: testHost),
                  let b = Bundle(url: url.deletingLastPathComponent()) else {
                return Bundle.main
            }
            return b
        }()

        let candidates: [Bundle] = [hostBundle, .main, bundle]
        for candidate in candidates {
            if let url = candidate.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") {
                let data = try Data(contentsOf: url)
                let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                if let dict = plist as? [String: Any] {
                    return dict
                }
            }
        }
        XCTFail("PrivacyInfo.xcprivacy not found in any candidate bundle")
        return [:]
    }

    func test_tracking_isFalse() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
    }

    func test_trackingDomains_isEmpty() throws {
        let manifest = try loadManifest()
        let domains = manifest["NSPrivacyTrackingDomains"] as? [Any] ?? []
        XCTAssertTrue(domains.isEmpty)
    }

    func test_collectedDataTypes_isEmpty() throws {
        let manifest = try loadManifest()
        let collected = manifest["NSPrivacyCollectedDataTypes"] as? [Any] ?? []
        XCTAssertTrue(collected.isEmpty, "expected zero collected data types, got \(collected.count)")
    }

    func test_accessedAPITypes_containsUserDefaultsWithCA92_1() throws {
        let manifest = try loadManifest()
        let accessed = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []
        let userDefaults = accessed.first { entry in
            (entry["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        XCTAssertNotNil(userDefaults, "missing UserDefaults entry in NSPrivacyAccessedAPITypes")
        let reasons = userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
        XCTAssertTrue(reasons.contains("CA92.1"), "expected reason CA92.1 in \(reasons)")
    }
}
