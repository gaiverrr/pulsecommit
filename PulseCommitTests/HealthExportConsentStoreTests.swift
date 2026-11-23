import XCTest
@testable import PulseCommit

final class HealthExportConsentStoreTests: XCTestCase {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "HealthExportConsentStoreTests.\(UUID().uuidString)")!
    }

    private func github(categories: Set<String> = ["steps"], version: String = "1") -> HealthExportConsentScope {
        HealthExportConsentScope(
            destination: .github(owner: "octocat", repo: "health", branch: "main", subdir: "exports"),
            enabledCategoryIds: categories,
            disclosureVersion: version
        )
    }

    private func telegram(categories: Set<String> = ["steps"], chatID: String = "-100123", threadID: Int? = 42) -> HealthExportConsentScope {
        HealthExportConsentScope(
            destination: .telegram(chatID: chatID, messageThreadID: threadID),
            enabledCategoryIds: categories,
            disclosureVersion: "1"
        )
    }

    func test_acceptanceIsIndependentAndPersistsTimestampAndVersion() throws {
        let defaults = defaults()
        let acceptedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let store = HealthExportConsentStore(defaults: defaults, clock: { acceptedAt })

        store.accept(github())

        XCTAssertTrue(store.hasCurrentConsent(for: github()))
        XCTAssertFalse(store.hasCurrentConsent(for: telegram()))
        XCTAssertEqual(store.record(for: .github)?.acceptedAt, acceptedAt)
        XCTAssertEqual(store.record(for: .github)?.scope.disclosureVersion, "1")
    }

    func test_scopeChangesAndAtoBtoAInvalidationRequireFreshConsent() {
        let store = HealthExportConsentStore(defaults: defaults())
        store.accept(github())

        XCTAssertFalse(store.hasCurrentConsent(for: github(categories: ["sleep"])))
        XCTAssertFalse(store.hasCurrentConsent(for: HealthExportConsentScope(
            destination: .github(owner: "octocat", repo: "health", branch: "release", subdir: "exports"),
            enabledCategoryIds: ["steps"], disclosureVersion: "1"
        )))
        XCTAssertFalse(store.hasCurrentConsent(for: github(version: "2")))

        store.invalidate(.github)
        XCTAssertFalse(store.hasCurrentConsent(for: github()), "A → B → A must not revive the old receipt")
    }

    func test_telegramChatTopicAndResetInvalidate() {
        let store = HealthExportConsentStore(defaults: defaults())
        store.accept(telegram())

        XCTAssertFalse(store.hasCurrentConsent(for: telegram(chatID: "-100999")))
        XCTAssertFalse(store.hasCurrentConsent(for: telegram(threadID: 7)))
        store.reset()
        XCTAssertFalse(store.hasCurrentConsent(for: telegram()))
    }

    func test_encodedReceiptContainsNoTokenOrHealthPayload() throws {
        let defaults = defaults()
        let store = HealthExportConsentStore(defaults: defaults)
        store.accept(telegram())

        let data = try XCTUnwrap(defaults.data(forKey: HealthExportConsentStore.storageKey(for: .telegram)))
        let encoded = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(encoded.contains("bot-token"))
        XCTAssertFalse(encoded.contains("access_token"))
        XCTAssertFalse(encoded.contains("samples"))
        XCTAssertTrue(encoded.contains("-100123"))
    }

    func test_preferencesChangesDisableAndResetInvalidateWithoutAtoBtoARevival() {
        let defaults = defaults()
        let store = HealthExportConsentStore(defaults: defaults)
        let preferences = PreferencesStore(defaults: defaults)
        preferences.bindConsentStore(store)
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "health"
        preferences.githubBranch = "main"
        preferences.githubSubdir = "exports"
        preferences.enabledCategoryIds = ["steps"]
        store.accept(github())

        preferences.githubBranch = "release"
        preferences.githubBranch = "main"
        XCTAssertFalse(store.hasCurrentConsent(for: github()))

        store.accept(github())
        preferences.githubExportEnabled = false
        preferences.githubExportEnabled = true
        XCTAssertFalse(store.hasCurrentConsent(for: github()))

        store.accept(github())
        preferences.reset()
        XCTAssertFalse(store.hasCurrentConsent(for: github()))
    }

}
