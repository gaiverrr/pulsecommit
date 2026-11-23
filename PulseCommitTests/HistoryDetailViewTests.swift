import XCTest
@testable import PulseCommit

@MainActor
final class HistoryDetailViewTests: XCTestCase {
    func test_fullErrorMessage_preservesAllCharacters() {
        let longMessage = String(repeating: "x", count: 500)
        let entry = HistoryEntry(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_060),
            status: .failed,
            sinks: ["telegram"],
            daysCovered: ["2026-05-14"],
            errorMessage: longMessage
        )
        let view = HistoryDetailView(entry: entry)
        XCTAssertEqual(view.fullErrorMessage.count, 500)
        XCTAssertEqual(view.fullErrorMessage, longMessage)
    }

    func test_telegramErrorDescription_isExposedVerbatim() {
        let message = "Telegram 400: Bad Request: chat not found"
        let entry = HistoryEntry(
            startedAt: Date(),
            finishedAt: Date(),
            status: .failed,
            sinks: ["telegram"],
            daysCovered: [],
            errorMessage: message
        )
        let view = HistoryDetailView(entry: entry)
        XCTAssertEqual(view.fullErrorMessage, message)
    }

    func test_missingErrorMessage_fallsBackToPlaceholder() {
        let entry = HistoryEntry(
            startedAt: Date(),
            finishedAt: Date(),
            status: .failed,
            sinks: [],
            daysCovered: []
        )
        let view = HistoryDetailView(entry: entry)
        XCTAssertEqual(view.fullErrorMessage, "export failed")
    }

    func test_shortHash_usesGithubShaWhenAvailable() {
        let entry = HistoryEntry(
            startedAt: Date(),
            finishedAt: Date(),
            status: .success,
            sinks: ["github"],
            daysCovered: ["2026-05-14"],
            githubCommitSha: "abcdef0123456789"
        )
        let view = HistoryDetailView(entry: entry)
        XCTAssertEqual(view.shortHash, "abcdef01")
    }
}
