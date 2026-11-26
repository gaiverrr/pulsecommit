import XCTest
import SwiftUI
import UIKit
@testable import PulseCommit

@MainActor
final class DestinationsToggleTests: XCTestCase {
    private func ephemeralDefaults() -> UserDefaults {
        let suite = "DestinationsToggleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_githubToggleBinding_writesToPreferences() {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        XCTAssertTrue(preferences.githubExportEnabled)

        let binding = Binding<Bool>(
            get: { preferences.githubExportEnabled },
            set: { preferences.githubExportEnabled = $0 }
        )

        binding.wrappedValue = false
        XCTAssertFalse(preferences.githubExportEnabled)
        XCTAssertFalse(binding.wrappedValue)

        binding.wrappedValue = true
        XCTAssertTrue(preferences.githubExportEnabled)
    }

    func test_telegramToggleBinding_writesToPreferences() {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        XCTAssertTrue(preferences.telegramExportEnabled)

        let binding = Binding<Bool>(
            get: { preferences.telegramExportEnabled },
            set: { preferences.telegramExportEnabled = $0 }
        )

        binding.wrappedValue = false
        XCTAssertFalse(preferences.telegramExportEnabled)

        binding.wrappedValue = true
        XCTAssertTrue(preferences.telegramExportEnabled)
    }

    func test_destinationsView_instantiatesWithContainer() {
        // Smoke: building the view with a full AppContainer must not crash and
        // must observe the persistent export-enabled flag through the
        // container's preferences. The .onAppear handler reads from
        // preferences; constructing the view itself does not, but this guards
        // against compile-time regressions to the view's dependencies.
        let secrets: any SecretsStore = InMemorySecretsStore()
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubExportEnabled = false

        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: try! HistoryStore.inMemory(),
            healthStore: HealthStoreClient(),
            registry: DefaultRegistryFactory.make(store: HealthStoreClient()),
            orchestratorFactory: { _ in
                fatalError("not used in this test")
            }
        )

        let path = Binding<[RootTabView.DestinationsRoute]>(get: { [] }, set: { _ in })
        let view = DestinationsView(path: path).environmentObject(container)
        XCTAssertNotNil(view)
        XCTAssertFalse(container.preferences.githubExportEnabled)
    }

    func test_toggleState_unconfiguredShowsOffEvenWhenPreferenceIsOn() {
        XCTAssertFalse(DestinationsView.toggleIsOn(configured: false, enabled: true))
        XCTAssertFalse(DestinationsView.toggleIsOn(configured: false, enabled: false))
    }

    func test_toggleState_configuredFollowsPreference() {
        XCTAssertTrue(DestinationsView.toggleIsOn(configured: true, enabled: true))
        XCTAssertFalse(DestinationsView.toggleIsOn(configured: true, enabled: false))
    }

    func test_unconfiguredRow_leavesStoredPreferenceUntouched() async throws {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        let healthStore = HealthStoreClient()
        let container = AppContainer(
            secrets: InMemorySecretsStore(),
            preferences: preferences,
            history: try HistoryStore.inMemory(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            orchestratorFactory: { _ in fatalError("not used in this test") }
        )
        let path = Binding<[RootTabView.DestinationsRoute]>(get: { [] }, set: { _ in })
        let host = UIHostingController(rootView: DestinationsView(path: path).environmentObject(container))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(preferences.githubExportEnabled)
        XCTAssertTrue(preferences.telegramExportEnabled)
        XCTAssertTrue(preferences.webhookExportEnabled)
    }

    func test_renderDestinationsWithConfiguredAndUnconfiguredRows() async throws {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        let secrets = InMemorySecretsStore()
        try await secrets.set("123456:ABCDEF", for: "tg_bot_token")
        try await secrets.set("-1001234567890", for: "tg_chat_id")
        let healthStore = HealthStoreClient()
        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: try HistoryStore.inMemory(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            orchestratorFactory: { _ in fatalError("not used in this test") }
        )
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: DestinationsView(path: .constant([]))
            .environmentObject(container)
            .preferredColorScheme(.dark))
        let window = UIWindow(frame: frame)
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 800_000_000)

        let image = UIGraphicsImageRenderer(size: frame.size).image { _ in
            host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        let png = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(png.count, 10_000)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "destinations-toggle-state"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
