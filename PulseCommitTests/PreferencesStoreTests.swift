import XCTest
import HealthCore
@testable import PulseCommit

final class PreferencesStoreTests: XCTestCase {
    private func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "PreferencesStoreTests.\(name).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_reviewPromptFiresOnlyAtSuccessfulExportMilestonesAndResetClearsTheCount() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        let prompts = (1...50).filter { _ in store.recordSuccessfulManualExport() }
        XCTAssertEqual(prompts, [3, 15, 50])
        XCTAssertFalse(PreferencesStore(defaults: defaults).recordSuccessfulManualExport())

        store.reset()
        XCTAssertFalse(store.recordSuccessfulManualExport())
        XCTAssertFalse(store.recordSuccessfulManualExport())
        XCTAssertTrue(store.recordSuccessfulManualExport())
    }

    func test_enabledCategoryIds_seedsAllMVPIdsOnFirstRead() {
        let store = PreferencesStore(defaults: makeDefaults())
        let ids = store.enabledCategoryIds
        XCTAssertEqual(ids, PreferencesStore.defaultCategoryIds)
        XCTAssertEqual(ids.count, 15)
    }

    func test_healthPermissionNoticeDismissal_persistsAcrossStoresAndResetRestoresIt() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        XCTAssertFalse(store.healthPermissionNoticeDismissed)

        store.healthPermissionNoticeDismissed = true
        XCTAssertTrue(PreferencesStore(defaults: defaults).healthPermissionNoticeDismissed)

        store.reset()
        XCTAssertFalse(PreferencesStore(defaults: defaults).healthPermissionNoticeDismissed)
    }

    func test_zoneBoundariesRoundTripAndReset() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.heartRateZoneConfiguration)
        let configuration = HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!
        store.heartRateZoneConfiguration = configuration
        XCTAssertEqual(store.heartRateZoneConfiguration, configuration)
        store.reset()
        XCTAssertNil(store.heartRateZoneConfiguration)
    }

    func test_invalidStoredZoneBoundariesAreIgnored() {
        let defaults = makeDefaults()
        defaults.set([120, 100, 140, 160], forKey: PreferencesStore.Key.heartRateZoneBounds)
        XCTAssertNil(PreferencesStore(defaults: defaults).heartRateZoneConfiguration)
    }

    func test_enabledCategoryIds_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        store.enabledCategoryIds = ["steps", "sleep"]
        XCTAssertEqual(store.enabledCategoryIds, ["steps", "sleep"])
    }

    func test_enabledCategoryIds_canBeClearedWithoutReseeding() {
        let store = PreferencesStore(defaults: makeDefaults())
        store.enabledCategoryIds = []
        XCTAssertEqual(store.enabledCategoryIds, [])
    }



    func test_telegramVerbosity_defaultsStandard_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertEqual(store.telegramVerbosity, "standard")
        store.telegramVerbosity = "compact"
        XCTAssertEqual(store.telegramVerbosity, "compact")
    }

    func test_githubOwner_defaultsNil_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.githubOwner)
        store.githubOwner = "octocat"
        XCTAssertEqual(store.githubOwner, "octocat")
        store.githubOwner = nil
        XCTAssertNil(store.githubOwner)
    }

    func test_githubRepo_defaultsNil_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.githubRepo)
        store.githubRepo = "health-export"
        XCTAssertEqual(store.githubRepo, "health-export")
        store.githubRepo = nil
        XCTAssertNil(store.githubRepo)
    }

    func test_githubBranch_defaultsNil_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.githubBranch)
        store.githubBranch = "main"
        XCTAssertEqual(store.githubBranch, "main")
        store.githubBranch = nil
        XCTAssertNil(store.githubBranch)
    }

    func test_githubSubdir_defaultsNil_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.githubSubdir)
        store.githubSubdir = "data/health"
        XCTAssertEqual(store.githubSubdir, "data/health")
        store.githubSubdir = nil
        XCTAssertNil(store.githubSubdir)
    }

    func test_telegramThreadId_defaultsNil_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.telegramThreadId)
        store.telegramThreadId = 42
        XCTAssertEqual(store.telegramThreadId, 42)
        store.telegramThreadId = -7
        XCTAssertEqual(store.telegramThreadId, -7)
        store.telegramThreadId = nil
        XCTAssertNil(store.telegramThreadId)
    }

    func test_githubExportEnabled_defaultsTrue_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertTrue(store.githubExportEnabled)
        store.githubExportEnabled = false
        XCTAssertFalse(store.githubExportEnabled)
        store.githubExportEnabled = true
        XCTAssertTrue(store.githubExportEnabled)
    }

    func test_telegramExportEnabled_defaultsTrue_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertTrue(store.telegramExportEnabled)
        store.telegramExportEnabled = false
        XCTAssertFalse(store.telegramExportEnabled)
        store.telegramExportEnabled = true
        XCTAssertTrue(store.telegramExportEnabled)
    }

    func test_exportEnabledFlags_useDocumentedUserDefaultsKeys() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.githubExportEnabled = false
        store.telegramExportEnabled = false
        XCTAssertEqual(defaults.bool(forKey: "pulse_commit.github.export_enabled"), false)
        XCTAssertEqual(defaults.bool(forKey: "pulse_commit.telegram.export_enabled"), false)
    }

    func test_githubInstallationId_defaultsNil_roundTrip() {
        let store = PreferencesStore(defaults: makeDefaults())
        XCTAssertNil(store.githubInstallationId)
        store.githubInstallationId = 12345678
        XCTAssertEqual(store.githubInstallationId, 12345678)
        store.githubInstallationId = nil
        XCTAssertNil(store.githubInstallationId)
    }
}
