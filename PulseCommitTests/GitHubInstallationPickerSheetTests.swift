import XCTest
@testable import PulseCommit

@MainActor
final class GitHubInstallationPickerSheetTests: XCTestCase {
    func test_loadInstallationsList_setsLoadedOnSuccess() async {
        let installations = [
            GitHubInstallation(id: 1, account: "octocat"),
            GitHubInstallation(id: 2, account: "acme")
        ]
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { installations },
            loadRepositories: { _ in [] },
            persist: { _, _ in },
            onDismiss: {}
        )
        vm.loadInstallationsList()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.installations, installations)
    }

    func test_loadInstallationsList_setsFailedOnError() async {
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { throw GitHubInstallationPickerError.unauthorized },
            loadRepositories: { _ in [] },
            persist: { _, _ in },
            onDismiss: {}
        )
        vm.loadInstallationsList()
        try? await Task.sleep(nanoseconds: 50_000_000)
        if case .failed = vm.state {} else { XCTFail("expected failed, got \(vm.state)") }
    }

    func test_selectInstallation_loadsRepositories() async {
        let repos = [GitHubRepo(fullName: "octocat/hello", defaultBranch: "main")]
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { [] },
            loadRepositories: { _ in repos },
            persist: { _, _ in },
            onDismiss: {}
        )
        vm.selectInstallation(GitHubInstallation(id: 1, account: "octocat"))
        XCTAssertEqual(vm.step, .repositories(installationId: 1, account: "octocat"))
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(vm.state, .loaded)
        XCTAssertEqual(vm.repositories, repos)
    }

    func test_selectRepository_callsPersistAndDismiss() {
        var persisted: (GitHubInstallation, GitHubRepo)?
        var dismissed = false
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { [] },
            loadRepositories: { _ in [] },
            persist: { installation, repo in persisted = (installation, repo) },
            onDismiss: { dismissed = true }
        )
        vm.step = .repositories(installationId: 42, account: "acme")
        let repo = GitHubRepo(fullName: "acme/widgets", defaultBranch: "trunk")
        vm.selectRepository(repo)
        XCTAssertEqual(persisted?.0.id, 42)
        XCTAssertEqual(persisted?.0.account, "acme")
        XCTAssertEqual(persisted?.1, repo)
        XCTAssertTrue(dismissed)
    }

    func test_selectRepository_doesNothingFromInstallationsStep() {
        var persistCalled = false
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { [] },
            loadRepositories: { _ in [] },
            persist: { _, _ in persistCalled = true },
            onDismiss: {}
        )
        vm.selectRepository(GitHubRepo(fullName: "x/y", defaultBranch: "main"))
        XCTAssertFalse(persistCalled)
    }

    func test_backToInstallations_resetsStep() {
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { [] },
            loadRepositories: { _ in [] },
            persist: { _, _ in },
            onDismiss: {}
        )
        vm.step = .repositories(installationId: 1, account: "octocat")
        vm.backToInstallations()
        XCTAssertEqual(vm.step, .installations)
    }

    func test_cancel_callsDismiss() {
        var dismissed = false
        let vm = GitHubInstallationPickerViewModel(
            loadInstallations: { [] },
            loadRepositories: { _ in [] },
            persist: { _, _ in },
            onDismiss: { dismissed = true }
        )
        vm.cancel()
        XCTAssertTrue(dismissed)
    }

    func test_live_persistWritesOwnerRepoBranchInstallationId() {
        let defaults = UserDefaults(suiteName: "GitHubInstallationPickerSheetTests-\(UUID())")!
        defaults.removePersistentDomain(forName: "GitHubInstallationPickerSheetTests")
        let prefs = PreferencesStore(defaults: defaults)
        var completed = false
        let vm = GitHubInstallationPickerViewModel.live(
            picker: GitHubInstallationPicker(),
            token: { "tok" },
            preferences: prefs,
            onComplete: { completed = true },
            onDismiss: {}
        )
        vm.step = .repositories(installationId: 7, account: "octocat")
        vm.selectRepository(GitHubRepo(fullName: "octocat/hello", defaultBranch: "main"))
        XCTAssertEqual(prefs.githubOwner, "octocat")
        XCTAssertEqual(prefs.githubRepo, "hello")
        XCTAssertEqual(prefs.githubInstallationId, 7)
        XCTAssertEqual(prefs.githubBranch, "main")
        XCTAssertTrue(completed)
    }
}
