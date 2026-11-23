import SwiftUI
import UIKit
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class TelegramDestinationConsentPersistenceTests: XCTestCase {
    func test_openingTelegramScreenWithSavedSettingsKeepsExportConsent() async throws {
        let suite = "TelegramDestinationConsentPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let secrets = ReadCountingSecretsStore()
        try await secrets.set("123456789:AAEexampleexampleexampleexample", for: "tg_bot_token")
        try await secrets.set("-1001234567890", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: defaults)
        preferences.telegramExportEnabled = true
        let healthStore = HealthStoreClient()
        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: HistoryStore.noOp(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            consentStore: HealthExportConsentStore(defaults: defaults),
            automaticWorkoutConsentStore: AutomaticWorkoutConsentStore(defaults: defaults),
            orchestratorFactory: { _ in fatalError("No export in this test") }
        )
        let currentScope = await container.currentConsentScope(for: .telegram)
        let scope = try XCTUnwrap(currentScope)
        let accepted = await container.acceptConsentIfCurrent(scope)
        XCTAssertTrue(accepted)
        preferences.automaticWorkoutTelegramEnabled = true

        let baselineReads = await secrets.chatIDReads
        let frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        let host = UIHostingController(rootView: NavigationStack {
            TelegramDestinationView().environmentObject(container)
        })
        let window = UIWindow(frame: frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        var waited = 0
        while await secrets.chatIDReads == baselineReads, waited < 100 {
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
            waited += 1
        }
        let chatIDReads = await secrets.chatIDReads
        XCTAssertGreaterThan(chatIDReads, baselineReads)
        for _ in 0..<10 {
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(container.consentStore.hasCurrentConsent(for: scope))
        XCTAssertTrue(preferences.automaticWorkoutTelegramEnabled)
    }
}

private actor ReadCountingSecretsStore: SecretsStore {
    private var values: [String: String] = [:]
    private(set) var chatIDReads = 0

    func get(_ key: String) async throws -> String? {
        if key == "tg_chat_id" { chatIDReads += 1 }
        return values[key]
    }

    func set(_ value: String?, for key: String) async throws {
        values[key] = value
    }
}
