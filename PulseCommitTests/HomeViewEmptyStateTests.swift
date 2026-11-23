import XCTest
@testable import PulseCommit

@MainActor
final class HomeViewEmptyStateTests: XCTestCase {
    private func makeView(github: Bool, telegram: Bool) -> HomeView {
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
            recentCommits: [],
            recentCommitsBranchHint: nil,
            healthPermissionRequestCompleted: false,
            githubConfigured: github,
            telegramConfigured: telegram
        )
    }

    func test_isEmptyState_trueWhenNeitherDestinationConfigured() {
        XCTAssertTrue(makeView(github: false, telegram: false).isEmptyState)
    }

    func test_isEmptyState_falseWhenGitHubConfigured() {
        XCTAssertFalse(makeView(github: true, telegram: false).isEmptyState)
    }

    func test_isEmptyState_falseWhenTelegramConfigured() {
        XCTAssertFalse(makeView(github: false, telegram: true).isEmptyState)
    }
}
