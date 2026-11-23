import XCTest

final class LegalDocsTests: XCTestCase {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        let url = repoRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    func test_privacyPolicy_existsAndHasRequiredHeadings() throws {
        let body = try read("docs/legal/privacy-policy.md")
        let required = [
            "## What we collect",
            "## Where your data goes",
            "## How to revoke",
            "## How to delete data",
            "## Third-party services we depend on",
            "## No advertising / no data brokers / no analytics",
            "## HealthKit-specific notice",
            "## Contact",
        ]
        for heading in required {
            XCTAssertTrue(body.contains(heading), "privacy-policy.md missing heading: \(heading)")
        }
        XCTAssertTrue(body.contains("Pulse Commit has no servers. No developer collects, stores, or sees your data."),
                      "privacy-policy.md missing dev-honest opening line")
        XCTAssertTrue(body.contains("api.github.com"), "privacy-policy.md must name api.github.com explicitly")
        XCTAssertTrue(body.contains("api.telegram.org"), "privacy-policy.md must name api.telegram.org explicitly")
        XCTAssertTrue(body.contains("hi@pulsecommit.app"), "privacy-policy.md must include contact email")
        XCTAssertTrue(body.contains("separately opt in to automatic finished-workout messages"))
        XCTAssertTrue(body.contains("manual exports you explicitly trigger or automatic finished-workout delivery you separately authorize"))
        XCTAssertFalse(body.contains("only for the export you explicitly trigger"))
        XCTAssertTrue(body.contains("does not include route or GPS points"))
        XCTAssertTrue(body.contains("excluded from backup"))
    }

    func test_terms_existsAndHasRequiredHeadings() throws {
        let body = try read("docs/legal/terms.md")
        let required = [
            "## License",
            "## No warranty",
            "## Liability",
            "## Termination",
            "## Jurisdiction",
            "## Contact",
        ]
        for heading in required {
            XCTAssertTrue(body.contains(heading), "terms.md missing heading: \(heading)")
        }
        XCTAssertTrue(body.contains("hi@pulsecommit.app"), "terms.md must include contact email")
        XCTAssertTrue(body.contains("Pulse Commit is free."))
        XCTAssertFalse(body.contains("in-app purchase grants"))
        XCTAssertFalse(body.contains("trial is granted"))
    }

    func test_legalDocs_haveNoLawyerVoice() throws {
        let forbidden = ["WHEREAS", "HEREINAFTER", "HEREBY", "HERETOFORE"]
        for path in ["docs/legal/privacy-policy.md", "docs/legal/terms.md"] {
            let body = try read(path)
            for word in forbidden {
                XCTAssertFalse(body.contains(word), "\(path) contains lawyer-voice word: \(word)")
            }
        }
    }
}
