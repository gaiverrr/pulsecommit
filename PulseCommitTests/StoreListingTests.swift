import XCTest

final class StoreListingTests: XCTestCase {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        let url = repoRoot().appendingPathComponent(relativePath)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func extractField(_ body: String, heading: String) -> String? {
        guard let range = body.range(of: "## \(heading)\n") else { return nil }
        let rest = body[range.upperBound...]
        var lines: [String] = []
        for line in rest.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.hasPrefix("## ") || s.hasPrefix("---") { break }
            lines.append(s)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func test_listing_existsAndContainsRequiredSections() throws {
        let body = try read("docs/store/listing.md")
        let required = [
            "## App Name",
            "## Subtitle",
            "## Promotional Text",
            "## Description",
            "## Keywords",
            "## URLs",
            "## Age Rating",
            "## Category",
            "## Pricing",
            "## Privacy nutrition",
        ]
        for heading in required {
            XCTAssertTrue(body.contains(heading), "listing.md missing heading: \(heading)")
        }
    }

    func test_appName_isWithinThirtyCharLimit() throws {
        let body = try read("docs/store/listing.md")
        let name = extractField(body, heading: "App Name") ?? ""
        XCTAssertEqual(name, "Pulse Commit: Health Export")
        XCTAssertLessThanOrEqual(name.count, 30, "App name is \(name.count) chars (limit 30)")
    }

    func test_subtitle_isWithinThirtyCharLimit() throws {
        let body = try read("docs/store/listing.md")
        let subtitle = extractField(body, heading: "Subtitle") ?? ""
        let firstLine = subtitle.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertFalse(firstLine.isEmpty, "Subtitle field must not be empty")
        XCTAssertLessThanOrEqual(firstLine.count, 30,
                                  "Subtitle '\(firstLine)' is \(firstLine.count) chars (limit 30)")
    }

    func test_promotionalText_isWithinOneSeventyCharLimit() throws {
        let body = try read("docs/store/listing.md")
        let promo = extractField(body, heading: "Promotional Text") ?? ""
        let firstLine = promo.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertFalse(firstLine.isEmpty, "Promotional Text must not be empty")
        XCTAssertLessThanOrEqual(firstLine.count, 170,
                                  "Promotional Text is \(firstLine.count) chars (limit 170)")
    }

    func test_keywords_areWithinOneHundredCharLimit() throws {
        let body = try read("docs/store/listing.md")
        guard let range = body.range(of: "## Keywords\n") else {
            XCTFail("Keywords section missing"); return
        }
        let rest = body[range.upperBound...]
        let codeFence = rest.range(of: "```\n")
        XCTAssertNotNil(codeFence, "Keywords must be inside a fenced block")
        let after = rest[codeFence!.upperBound...]
        let end = after.range(of: "\n```")
        XCTAssertNotNil(end, "Keywords block must be closed")
        let keywords = String(after[..<end!.lowerBound])
        let byteCount = keywords.lengthOfBytes(using: .utf8)
        XCTAssertLessThanOrEqual(byteCount, 100,
                                  "Keywords '\(keywords)' is \(byteCount) UTF-8 bytes (limit 100)")
        XCTAssertTrue(keywords.contains("healthkit"), "Keywords must include healthkit")
        XCTAssertTrue(keywords.contains("telegram"), "Keywords must include telegram")
        let name = (extractField(body, heading: "App Name") ?? "").lowercased()
        let subtitle = (extractField(body, heading: "Subtitle") ?? "").lowercased()
        let indexedWords = Set((name + " " + subtitle).split(whereSeparator: { !$0.isLetter }).map(String.init))
        let keywordList = keywords.split(separator: ",").map(String.init)
        XCTAssertFalse(keywordList.contains { $0.contains(" ") }, "Keywords must be comma-separated without spaces")
        XCTAssertTrue(indexedWords.isDisjoint(with: keywordList),
                      "Keywords repeat name/subtitle words: \(indexedWords.intersection(keywordList))")
        XCTAssertEqual(Set(keywordList).count, keywordList.count, "Keywords must not repeat")
    }

    func test_keywords_containNoThirdPartyTrademarks() throws {
        let body = try read("docs/store/listing.md")
        guard let range = body.range(of: "## Keywords\n```\n") ?? body.range(of: "## Keywords\n\n```\n") else {
            XCTFail("Keywords section missing"); return
        }
        let rest = body[range.upperBound...]
        let keywords = String(rest[..<rest.range(of: "\n```")!.lowerBound]).lowercased()
        for brand in ["openclaw", "hermes", "claude", "chatgpt", "gemini", "openai", "n8n"] {
            XCTAssertFalse(keywords.contains(brand), "Keywords must not contain trademark: \(brand)")
        }
    }

    func test_description_isPlainTextWithinFourThousandCharacterLimit() throws {
        let body = try read("docs/store/listing.md")
        let description = extractField(body, heading: "Description") ?? ""
        XCTAssertFalse(description.isEmpty, "Description must not be empty")
        XCTAssertLessThanOrEqual(
            description.count,
            4_000,
            "Description is \(description.count) characters (limit 4000)"
        )
        XCTAssertFalse(description.contains("<a "), "Description must be plain text, not HTML")
    }

    func test_description_containsHeroLineAndAntiPositioningAndFreePrice() throws {
        let body = try read("docs/store/listing.md")
        XCTAssertTrue(
            body.contains("Daily Apple Health exports for your own AI agent, or any script or service that reads JSON."),
            "Description must contain the hero line verbatim"
        )
        XCTAssertTrue(
            body.contains("If you don't have a GitHub account or a Telegram bot, this app is not for you."),
            "Description must contain the anti-positioning sentence verbatim"
        )
        XCTAssertTrue(body.contains("Pulse Commit 1.0 is free."))
        XCTAssertFalse(body.contains("$9.99"), "1.0 is free: no stale price")
        XCTAssertTrue(body.contains("optional, separate consent can send one text-only Telegram message"))
        XCTAssertFalse(body.contains("Pro unlock"))
        XCTAssertFalse(body.contains("trial run"))
        XCTAssertTrue(body.contains("manual exports you trigger or automatic finished-workout delivery you separately authorize"))
        XCTAssertFalse(body.contains("sent only during an export"))
        XCTAssertFalse(body.contains("only when the user exports"))
    }

    func test_listing_namesOutboundHostsExplicitly() throws {
        let body = try read("docs/store/listing.md")
        XCTAssertTrue(body.contains("api.github.com"), "Must name api.github.com")
        XCTAssertTrue(body.contains("api.telegram.org"), "Must name api.telegram.org")
        XCTAssertTrue(body.contains("the webhook host you enter"), "Must disclose the user-supplied webhook host")
    }

    func test_pricingRecordsFreeReleaseWithoutClaimingAppStoreConnectState() throws {
        let body = try read("docs/store/listing.md")
        XCTAssertTrue(body.contains("Owner decision 2026-11-17: version 1.0 is free."))
        XCTAssertTrue(body.contains("App price in App Store Connect: Free. Account state: **NOT VERIFIED**."))
        XCTAssertTrue(body.contains("must not be attached to the 1.0 version"))
        XCTAssertFalse(body.contains("app.pulsecommit.unlock"))
        XCTAssertFalse(body.contains("Restore Purchases"))
    }


    func test_ageRatingIsAnAccountGateRatherThanAStaleHardCodedAnswer() throws {
        let body = try read("docs/store/listing.md")
        let ageRating = extractField(body, heading: "Age Rating") ?? ""
        XCTAssertTrue(ageRating.contains("Pending Account Holder"))
        XCTAssertFalse(ageRating.hasPrefix("12+"), "the retired hard-coded rating must not be reused")
    }
}
