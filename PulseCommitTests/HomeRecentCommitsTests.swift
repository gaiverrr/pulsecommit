import XCTest
@testable import PulseCommit

@MainActor
final class HomeRecentCommitsTests: XCTestCase {
    private func makeView(rows: [HomeView.RecentCommitRow]) -> HomeView {
        let viewModel = HomeViewModel(
            runRequest: { _, _ in .success },
            enabledCategoryIds: { [] },
            enabledSinkIds: { [] }
        )
        return HomeView(
            viewModel: viewModel,
            deviceName: "iPhone 15",
            appVersion: "1.0.0",
            timezoneAbbreviation: "UTC",
            recentCommits: rows,
            recentCommitsBranchHint: "main · alice/health",
            healthPermissionRequestCompleted: true,
            githubConfigured: true,
            telegramConfigured: false
        )
    }

    private func row(_ sha: String?, ok: Bool = true) -> HomeView.RecentCommitRow {
        HomeView.RecentCommitRow(
            id: UUID(),
            shortSha: sha,
            dateLabel: "2026-05-13",
            timeAgo: "2m",
            summary: "exported 1 day",
            ok: ok
        )
    }

    func test_recentCommits_passesFourRowsToView() {
        let rows = [row("aaaaaaa"), row("bbbbbbb"), row("ccccccc"), row("ddddddd", ok: false)]
        let view = makeView(rows: rows)
        XCTAssertEqual(view.recentCommits.count, 4)
        XCTAssertEqual(view.recentCommits.first?.shortSha, "aaaaaaa")
        XCTAssertEqual(view.recentCommits.last?.ok, false)
    }

    func test_recentCommits_emptyArrayRendersEmptyState() {
        let view = makeView(rows: [])
        XCTAssertTrue(view.recentCommits.isEmpty)
        // The card body itself should still render — verify it doesn't trap by
        // creating a body host. Rendering through ViewInspector is overkill;
        // building the body is enough to catch crashes/compile-time issues.
        _ = view.recentCommitsCard
    }
}
