import XCTest
@testable import PulseCommit

@MainActor
final class GitHubSubdirEditSheetTests: XCTestCase {
    func test_isValid_acceptsAllowedCharacters() {
        XCTAssertTrue(GitHubSubdirEditViewModel.isValid(""))
        XCTAssertTrue(GitHubSubdirEditViewModel.isValid("health"))
        XCTAssertTrue(GitHubSubdirEditViewModel.isValid("health/exports"))
        XCTAssertTrue(GitHubSubdirEditViewModel.isValid("a/b/c-d_e"))
        XCTAssertTrue(GitHubSubdirEditViewModel.isValid("ABC_123"))
    }

    func test_isValid_rejectsDisallowedCharacters() {
        XCTAssertFalse(GitHubSubdirEditViewModel.isValid("has space"))
        XCTAssertFalse(GitHubSubdirEditViewModel.isValid("has.dot"))
        XCTAssertFalse(GitHubSubdirEditViewModel.isValid("../escape"))
        XCTAssertFalse(GitHubSubdirEditViewModel.isValid("a;b"))
        XCTAssertFalse(GitHubSubdirEditViewModel.isValid("emoji🚀"))
    }

    func test_save_persistsAndDismissesWhenValid() async {
        let persisted = expectation(description: "persist")
        let dismissed = expectation(description: "dismiss")
        var stored: String?

        let vm = GitHubSubdirEditViewModel(
            initial: "old",
            persist: { value in
                stored = value
                persisted.fulfill()
            },
            onDismiss: { dismissed.fulfill() }
        )
        vm.value = "health/exports"
        vm.save()

        await fulfillment(of: [persisted, dismissed], timeout: 1.0)
        XCTAssertEqual(stored, "health/exports")
    }

    func test_save_isNoOpWhenInvalid() async {
        var persisted = false
        var dismissed = false
        let vm = GitHubSubdirEditViewModel(
            initial: "",
            persist: { _ in persisted = true },
            onDismiss: { dismissed = true }
        )
        vm.value = "has space"
        XCTAssertFalse(vm.isValid)
        vm.save()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(persisted)
        XCTAssertFalse(dismissed)
    }

    func test_cancel_invokesDismissOnly() async {
        var persisted = false
        let dismissed = expectation(description: "dismiss")
        let vm = GitHubSubdirEditViewModel(
            initial: "x",
            persist: { _ in persisted = true },
            onDismiss: { dismissed.fulfill() }
        )
        vm.cancel()
        await fulfillment(of: [dismissed], timeout: 1.0)
        XCTAssertFalse(persisted)
    }

    func test_live_writesValueAndClearsOnEmpty() async {
        let suite = "test-subdir-edit-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = PreferencesStore(defaults: defaults)
        prefs.githubSubdir = "previous"

        let dismissed1 = expectation(description: "dismiss1")
        let vm1 = GitHubSubdirEditViewModel.live(
            initial: prefs.githubSubdir ?? "",
            preferences: prefs,
            onDismiss: { dismissed1.fulfill() }
        )
        vm1.value = "health"
        vm1.save()
        await fulfillment(of: [dismissed1], timeout: 1.0)
        XCTAssertEqual(prefs.githubSubdir, "health")

        let dismissed2 = expectation(description: "dismiss2")
        let vm2 = GitHubSubdirEditViewModel.live(
            initial: prefs.githubSubdir ?? "",
            preferences: prefs,
            onDismiss: { dismissed2.fulfill() }
        )
        vm2.value = ""
        vm2.save()
        await fulfillment(of: [dismissed2], timeout: 1.0)
        XCTAssertNil(prefs.githubSubdir)
    }
}
