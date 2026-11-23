import XCTest
import SwiftUI
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
}
