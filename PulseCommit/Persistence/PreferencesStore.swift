import Foundation
import HealthCore

final class PreferencesStore {
    enum Key {
        static let heartRateZoneBounds = "preferences.heartRateZoneBounds"
        static let enabledCategoryIds = "preferences.enabledCategoryIds"
        // Written by retired v1.0-beta controls; kept only so reset() wipes
        // stale values from existing installs.
        static let unitSystem = "preferences.unitSystem"
        // iCloud sync UI shipped briefly pre-release; no iCloud plumbing ever
        // existed. Retired; kept only so reset() wipes stale values.
        static let iCloudPreferencesSync = "preferences.iCloudPreferencesSync"
        // includeGitHubLink UI shipped briefly pre-release; link plumbing is v1.1.
        static let includeGitHubLinkInTelegram = "preferences.includeGitHubLinkInTelegram"
        static let telegramVerbosity = "preferences.telegramVerbosity"
        static let telegramThreadId = "tg_thread_id"
        static let backfillWindowDays = "preferences.backfillWindowDays"
        static let seeded = "preferences.seeded"
        static let githubOwner = "pulse-commit.github.owner"
        static let githubRepo = "pulse-commit.github.repo"
        static let githubBranch = "pulse-commit.github.branch"
        static let githubSubdir = "pulse-commit.github.subdir"
        static let githubInstallationId = "pulse-commit.github.installationId"
        static let githubExportEnabled = "pulse_commit.github.export_enabled"
        static let telegramExportEnabled = "pulse_commit.telegram.export_enabled"
        static let automaticWorkoutTelegramEnabled = "pulse_commit.telegram.automatic_workouts_enabled"
        static let automaticWorkoutRegistrationFailed = "pulse_commit.telegram.automatic_workouts_registration_failed"
        static let selectedPeriod = "pulse_commit.home.selected_period"
        static let healthPermissionNoticeDismissed = "pulse_commit.home.health_permission_notice_dismissed"
    }

    // Persisted period selection for the Home big-button. Values mirror the
    // menu options: "today" (default), "yesterday", "last_7_days",
    // "last_30_days", "custom". Unknown values are ignored and treated as
    // "today" — the menu UI is the only writer.
    static let defaultSelectedPeriod = "today"

    static let defaultCategoryIds: Set<String> = [
        "steps",
        "distance_walking_running",
        "heart_rate",
        "resting_heart_rate",
        "hrv_sdnn",
        "vo2_max",
        "active_energy",
        "activity_rings",
        "sleep",
        "respiratory_rate",
        "wrist_temperature",
        "workouts",
        "body_mass",
        "state_of_mind",
        "nutrition"
    ]

    private let defaults: UserDefaults
    private weak var consentStore: HealthExportConsentStore?
    private weak var automaticWorkoutConsentStore: AutomaticWorkoutConsentStore?
    private var automaticWorkoutConfigurationChanged: (@Sendable () -> Void)?
    private(set) var automaticWorkoutConfigurationRevision: UInt64 = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func bindConsentStore(_ consentStore: HealthExportConsentStore) {
        self.consentStore = consentStore
    }

    func bindAutomaticWorkoutConsentStore(_ consentStore: AutomaticWorkoutConsentStore) {
        self.automaticWorkoutConsentStore = consentStore
    }

    func bindAutomaticWorkoutConfigurationChanged(_ handler: @escaping @Sendable () -> Void) {
        automaticWorkoutConfigurationChanged = handler
    }

    private func invalidateAutomaticWorkoutDelivery() {
        automaticWorkoutConsentStore?.invalidate()
        defaults.set(false, forKey: Key.automaticWorkoutTelegramEnabled)
        automaticWorkoutConfigurationChanged?()
    }

    private func noteAutomaticWorkoutConfigurationChange() {
        automaticWorkoutConfigurationRevision &+= 1
    }

    var enabledCategoryIds: Set<String> {
        get {
            if !defaults.bool(forKey: Key.seeded) {
                defaults.set(Array(Self.defaultCategoryIds), forKey: Key.enabledCategoryIds)
                defaults.set(true, forKey: Key.seeded)
                return Self.defaultCategoryIds
            }
            let stored = defaults.array(forKey: Key.enabledCategoryIds) as? [String] ?? []
            return Set(stored)
        }
        set {
            if newValue != enabledCategoryIds {
                noteAutomaticWorkoutConfigurationChange()
                consentStore?.reset()
                invalidateAutomaticWorkoutDelivery()
            }
            defaults.set(Array(newValue), forKey: Key.enabledCategoryIds)
            defaults.set(true, forKey: Key.seeded)
        }
    }

    var heartRateZoneConfiguration: HeartRateZoneConfiguration? {
        get {
            guard let values = defaults.array(forKey: Key.heartRateZoneBounds) as? [Int] else { return nil }
            return HeartRateZoneConfiguration(lowerBoundsBPM: values)
        }
        set {
            if let newValue { defaults.set(newValue.lowerBoundsBPM, forKey: Key.heartRateZoneBounds) }
            else { defaults.removeObject(forKey: Key.heartRateZoneBounds) }
        }
    }

    var telegramVerbosity: String {
        get { defaults.string(forKey: Key.telegramVerbosity) ?? "standard" }
        set { defaults.set(newValue, forKey: Key.telegramVerbosity) }
    }

    var telegramThreadId: Int? {
        get {
            guard defaults.object(forKey: Key.telegramThreadId) != nil else { return nil }
            return defaults.integer(forKey: Key.telegramThreadId)
        }
        set {
            if newValue != telegramThreadId {
                noteAutomaticWorkoutConfigurationChange()
                consentStore?.invalidate(.telegram)
                invalidateAutomaticWorkoutDelivery()
            }
            if let value = newValue {
                defaults.set(value, forKey: Key.telegramThreadId)
            } else {
                defaults.removeObject(forKey: Key.telegramThreadId)
            }
        }
    }

    func reset() {
        noteAutomaticWorkoutConfigurationChange()
        for key in [
            Key.enabledCategoryIds,
            Key.heartRateZoneBounds,
            Key.unitSystem,
            Key.iCloudPreferencesSync,
            Key.includeGitHubLinkInTelegram,
            Key.telegramVerbosity,
            Key.telegramThreadId,
            Key.backfillWindowDays,
            Key.seeded,
            Key.githubOwner,
            Key.githubRepo,
            Key.githubBranch,
            Key.githubSubdir,
            Key.githubInstallationId,
            Key.githubExportEnabled,
            Key.telegramExportEnabled,
            Key.automaticWorkoutTelegramEnabled,
            Key.automaticWorkoutRegistrationFailed,
            Key.selectedPeriod,
            Key.healthPermissionNoticeDismissed
        ] {
            defaults.removeObject(forKey: key)
        }
        consentStore?.reset()
        automaticWorkoutConsentStore?.invalidate()
        automaticWorkoutConfigurationChanged?()
    }

    var githubOwner: String? {
        get { defaults.string(forKey: Key.githubOwner) }
        set {
            if newValue != githubOwner { consentStore?.invalidate(.github) }
            if let value = newValue { defaults.set(value, forKey: Key.githubOwner) }
            else { defaults.removeObject(forKey: Key.githubOwner) }
        }
    }

    var githubRepo: String? {
        get { defaults.string(forKey: Key.githubRepo) }
        set {
            if newValue != githubRepo { consentStore?.invalidate(.github) }
            if let value = newValue { defaults.set(value, forKey: Key.githubRepo) }
            else { defaults.removeObject(forKey: Key.githubRepo) }
        }
    }

    var githubBranch: String? {
        get { defaults.string(forKey: Key.githubBranch) }
        set {
            if newValue != githubBranch { consentStore?.invalidate(.github) }
            if let value = newValue { defaults.set(value, forKey: Key.githubBranch) }
            else { defaults.removeObject(forKey: Key.githubBranch) }
        }
    }

    var githubSubdir: String? {
        get { defaults.string(forKey: Key.githubSubdir) }
        set {
            if newValue != githubSubdir { consentStore?.invalidate(.github) }
            if let value = newValue { defaults.set(value, forKey: Key.githubSubdir) }
            else { defaults.removeObject(forKey: Key.githubSubdir) }
        }
    }

    var githubExportEnabled: Bool {
        get {
            if defaults.object(forKey: Key.githubExportEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.githubExportEnabled)
        }
        set {
            if newValue == false { consentStore?.invalidate(.github) }
            defaults.set(newValue, forKey: Key.githubExportEnabled)
        }
    }

    var telegramExportEnabled: Bool {
        get {
            if defaults.object(forKey: Key.telegramExportEnabled) == nil {
                return true
            }
            return defaults.bool(forKey: Key.telegramExportEnabled)
        }
        set {
            if newValue == false {
                if telegramExportEnabled { noteAutomaticWorkoutConfigurationChange() }
                consentStore?.invalidate(.telegram)
                invalidateAutomaticWorkoutDelivery()
            } else if !telegramExportEnabled {
                noteAutomaticWorkoutConfigurationChange()
            }
            defaults.set(newValue, forKey: Key.telegramExportEnabled)
        }
    }

    var automaticWorkoutTelegramEnabled: Bool {
        get { defaults.bool(forKey: Key.automaticWorkoutTelegramEnabled) }
        set {
            let changed = newValue != automaticWorkoutTelegramEnabled
            if changed {
                noteAutomaticWorkoutConfigurationChange()
            }
            if newValue == false { automaticWorkoutConsentStore?.invalidate() }
            defaults.set(newValue, forKey: Key.automaticWorkoutTelegramEnabled)
            if changed { automaticWorkoutConfigurationChanged?() }
        }
    }

    var automaticWorkoutRegistrationFailed: Bool {
        get { defaults.bool(forKey: Key.automaticWorkoutRegistrationFailed) }
        set {
            let changed = newValue != automaticWorkoutRegistrationFailed
            defaults.set(newValue, forKey: Key.automaticWorkoutRegistrationFailed)
            if changed { automaticWorkoutConfigurationChanged?() }
        }
    }

    var selectedPeriod: String {
        get { defaults.string(forKey: Key.selectedPeriod) ?? Self.defaultSelectedPeriod }
        set { defaults.set(newValue, forKey: Key.selectedPeriod) }
    }

    var healthPermissionNoticeDismissed: Bool {
        get { defaults.bool(forKey: Key.healthPermissionNoticeDismissed) }
        set { defaults.set(newValue, forKey: Key.healthPermissionNoticeDismissed) }
    }

    var githubInstallationId: Int? {
        get {
            guard defaults.object(forKey: Key.githubInstallationId) != nil else { return nil }
            return defaults.integer(forKey: Key.githubInstallationId)
        }
        set {
            if let value = newValue {
                defaults.set(value, forKey: Key.githubInstallationId)
            } else {
                defaults.removeObject(forKey: Key.githubInstallationId)
            }
        }
    }
}
