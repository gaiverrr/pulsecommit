import XCTest
@testable import HealthCore

final class MarkdownV2EscaperTests: XCTestCase {
    func testEscapesUnderscoreAndAsterisk() {
        XCTAssertEqual(MarkdownV2Escaper.escape("_foo_*bar*"), "\\_foo\\_\\*bar\\*")
    }

    func testEscapesTrailingDot() {
        XCTAssertEqual(MarkdownV2Escaper.escape("end."), "end\\.")
    }

    func testEscapesParens() {
        XCTAssertEqual(MarkdownV2Escaper.escape("(hi)"), "\\(hi\\)")
    }

    func testEscapesAllSpecials() {
        let raw = "_*[]()~`>#+-=|{}.!\\"
        let escaped = MarkdownV2Escaper.escape(raw)
        for ch in raw {
            XCTAssertTrue(escaped.contains("\\\(ch)"), "Missing escape for \(ch)")
        }
    }

    func testEscapeCodeContentEscapesOnlyBacktickAndBackslash() {
        XCTAssertEqual(MarkdownV2Escaper.escapeCodeContent("a`b\\c"), "a\\`b\\\\c")
    }

    func testEscapeCodeContentLeavesMarkdownReservedCharsUntouched() {
        // Inside a fenced block Telegram treats `.`, `-`, `(`, `_`, `*` as literal.
        let raw = "Steps: 12 483 · 7h 12m (P/C/F) end."
        XCTAssertEqual(MarkdownV2Escaper.escapeCodeContent(raw), raw)
    }

    func testChunkReturnsSingleChunkWhenUnderLimit() {
        let result = MarkdownV2Escaper.chunk("short", limit: 4096)
        XCTAssertEqual(result, ["short"])
    }

    func testChunkReturnsEmptyForEmptyInput() {
        XCTAssertEqual(MarkdownV2Escaper.chunk("", limit: 4096), [])
    }

    func testChunkSplitsLongInputUnderLimitAndPreservesContent() {
        let lines = (0..<3000).map { "line \($0)" }
        let original = lines.joined(separator: "\n")
        let limit = 4096

        let chunks = MarkdownV2Escaper.chunk(original, limit: limit)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, limit)
        }
        XCTAssertEqual(chunks.joined(), original)
    }

    func testChunkPrefersBlankLineBoundary() {
        let block = String(repeating: "a", count: 100)
        let input = block + "\n\n" + block + "\n\n" + block
        let chunks = MarkdownV2Escaper.chunk(input, limit: 210)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks[0].hasSuffix("\n\n"))
        XCTAssertEqual(chunks.joined(), input)
    }

    func testChunkFallsBackToHardCutWhenNoNewline() {
        let input = String(repeating: "x", count: 5000)
        let chunks = MarkdownV2Escaper.chunk(input, limit: 4096)
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].count, 4096)
        XCTAssertEqual(chunks.joined(), input)
    }

    func testChunkHardCutDoesNotSplitEscapeSequence() {
        let prefix = String(repeating: "x", count: 4095)
        let input = prefix + "\\.tail"
        let chunks = MarkdownV2Escaper.chunk(input, limit: 4096)
        XCTAssertEqual(chunks.joined(), input)
        XCTAssertFalse(chunks[0].hasSuffix("\\"), "Chunk must not end with a dangling backslash")
        XCTAssertTrue(chunks[1].hasPrefix("\\."), "Escape pair must stay in the next chunk")
    }

    func testChunkNewlineBoundaryDoesNotLeaveDanglingBackslash() {
        let prefix = String(repeating: "a", count: 4090)
        let input = prefix + "\\\nrest"
        let chunks = MarkdownV2Escaper.chunk(input, limit: 4096)
        XCTAssertEqual(chunks.joined(), input)
        for chunk in chunks.dropLast() {
            let trimmed = chunk.hasSuffix("\n") ? String(chunk.dropLast()) : chunk
            var trailing = 0
            for ch in trimmed.reversed() {
                if ch == "\\" { trailing += 1 } else { break }
            }
            XCTAssertTrue(trailing.isMultiple(of: 2), "Chunk leaves odd backslash run before newline")
        }
    }

    func testChunkHardCutKeepsLiteralBackslashPairTogether() {
        let prefix = String(repeating: "x", count: 4094)
        let input = prefix + "\\\\rest"
        let chunks = MarkdownV2Escaper.chunk(input, limit: 4096)
        XCTAssertEqual(chunks.joined(), input)
        XCTAssertTrue(chunks[0].hasSuffix("\\\\"), "Even backslash run must remain in head")
    }

    func testChunkClosesAndReopensFenceAcrossSplits() {
        let bodyLines = (0..<600).map { "  Metric \($0)      \($0 * 37) kcal" }
        let message = "🫀 *Pulse Commit · 2026\\-05\\-14*\n```\n"
            + bodyLines.joined(separator: "\n")
            + "\n```\n`schema_version: 1.0`"
        XCTAssertGreaterThan(message.count, 4096)

        let chunks = MarkdownV2Escaper.chunk(message, limit: 4096)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 4096, "Chunk exceeds limit after fence accounting")
            XCTAssertTrue(
                fenceLineCount(in: chunk).isMultiple(of: 2),
                "Chunk has unbalanced code fences:\n...\(chunk.suffix(60))"
            )
        }
        for chunk in chunks.dropLast() {
            XCTAssertTrue(chunk.hasSuffix("```"), "Chunk split inside a fence must close it")
        }
        for chunk in chunks.dropFirst() {
            XCTAssertTrue(chunk.hasPrefix("```\n"), "Continuation chunk must reopen the fence so rendering stays monospace")
        }
        XCTAssertEqual(
            strippingFenceLines(chunks.joined(separator: "\n")),
            strippingFenceLines(message),
            "Chunking must not lose or alter non-fence content"
        )
    }

    func testChunkWithoutFencesIsUnchangedByFenceHandling() {
        let block = String(repeating: "a", count: 100)
        let input = block + "\n\n" + block + "\n\n" + block
        let chunks = MarkdownV2Escaper.chunk(input, limit: 210)
        XCTAssertEqual(chunks.joined(), input)
    }

    func testChunkHardCutDoesNotSplitInsideInlineEntity() {
        let prefix = String(repeating: "x", count: 4080)
        let input = prefix + " *bold run that crosses the limit* tail"
        let chunks = MarkdownV2Escaper.chunk(input, limit: 4096)
        XCTAssertEqual(chunks.joined(), input)
        for chunk in chunks {
            XCTAssertTrue(
                unescapedCount(of: "*", in: chunk).isMultiple(of: 2),
                "Chunk splits inside a bold entity: ...\(chunk.suffix(40))"
            )
        }
    }

    func testChunkHardCutDoesNotSplitInsideUnderscoreEntity() {
        let prefix = String(repeating: "x", count: 4085)
        let input = prefix + " _italic span past limit_ tail"
        let chunks = MarkdownV2Escaper.chunk(input, limit: 4096)
        XCTAssertEqual(chunks.joined(), input)
        for chunk in chunks {
            XCTAssertTrue(
                unescapedCount(of: "_", in: chunk).isMultiple(of: 2),
                "Chunk splits inside an italic entity: ...\(chunk.suffix(40))"
            )
        }
    }

    private func fenceLineCount(in chunk: String) -> Int {
        chunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("```") }
            .count
    }

    private func strippingFenceLines(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix("```") }
            .joined(separator: "\n")
    }

    private func unescapedCount(of target: Character, in text: String) -> Int {
        var count = 0
        var escaped = false
        for ch in text {
            if escaped {
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == target {
                count += 1
            }
        }
        return count
    }
}
