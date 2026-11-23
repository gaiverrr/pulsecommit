import XCTest
@testable import PulseCommit

@MainActor
final class GitHubBranchPickerSheetTests: XCTestCase {
    func test_load_populatesBranches() async throws {
        let vm = GitHubBranchPickerViewModel(
            owner: "octocat",
            repo: "demo",
            loader: { _, _ in ["main", "develop", "feature/x"] },
            persist: { _ in },
            onDismiss: {}
        )

        vm.load()
        XCTAssertEqual(vm.state, .loading)

        try await waitUntil(timeout: 2.0) { vm.state == .loaded }
        XCTAssertEqual(vm.branches, ["main", "develop", "feature/x"])
    }

    func test_load_surfacesFailureMessage() async throws {
        struct Boom: Error {}
        let vm = GitHubBranchPickerViewModel(
            owner: "o",
            repo: "r",
            loader: { _, _ in throw Boom() },
            persist: { _ in },
            onDismiss: {}
        )

        vm.load()
        try await waitUntil(timeout: 2.0) {
            if case .failed = vm.state { return true }
            return false
        }
    }

    func test_filtered_appliesCaseInsensitiveSearch() {
        let vm = GitHubBranchPickerViewModel(
            owner: "o", repo: "r",
            loader: { _, _ in [] },
            persist: { _ in },
            onDismiss: {}
        )
        vm.branches = ["main", "develop", "feature/login", "Feature/Logout"]
        vm.search = "feat"
        XCTAssertEqual(vm.filtered, ["feature/login", "Feature/Logout"])
        vm.search = ""
        XCTAssertEqual(vm.filtered.count, 4)
    }

    func test_select_persistsBranchAndDismisses() async {
        let persisted = expectation(description: "persist called")
        let dismissed = expectation(description: "dismiss called")
        var persistedValue: String?

        let vm = GitHubBranchPickerViewModel(
            owner: "o", repo: "r",
            loader: { _, _ in [] },
            persist: { value in
                persistedValue = value
                persisted.fulfill()
            },
            onDismiss: { dismissed.fulfill() }
        )

        vm.select("develop")
        await fulfillment(of: [persisted, dismissed], timeout: 1.0)
        XCTAssertEqual(persistedValue, "develop")
    }

    func test_live_writesToPreferencesStore() async {
        let suite = "test-branch-picker-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = PreferencesStore(defaults: defaults)

        let dismissed = expectation(description: "dismissed")
        let vm = GitHubBranchPickerViewModel.live(
            owner: "o",
            repo: "r",
            fetcher: GitHubBranchFetcher(),
            token: { "t" },
            preferences: prefs,
            onDismiss: { dismissed.fulfill() }
        )

        vm.select("develop")
        await fulfillment(of: [dismissed], timeout: 1.0)
        XCTAssertEqual(prefs.githubBranch, "develop")
    }

    private func waitUntil(timeout: TimeInterval, _ predicate: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}
