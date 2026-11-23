import Foundation
import Security

/// Keychain items survive app uninstall on iOS. If a user uninstalls then
/// reinstalls Pulse Commit, stale GitHub OAuth tokens and the Telegram bot
/// token would be silently inherited by the new install — with no chance for
/// the user to revoke. On first launch we wipe every generic-password item
/// owned by our service so the reinstalled app starts from a clean slate.
///
/// Idempotent: a `UserDefaults` sentinel guarantees cleanup runs exactly
/// once per install. Subsequent launches are a no-op.
///
/// MUST run before any keychain read.
enum FirstLaunchCleanup {
    static let sentinelKey = "app.pulsecommit.installed"
    static let serviceIdentifier = "app.pulsecommit"

    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        service: String = serviceIdentifier,
        deleter: SecItemDeleting = SecItemDeleter()
    ) {
        guard defaults.object(forKey: sentinelKey) == nil else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        _ = deleter.delete(query: query as CFDictionary)
        defaults.set(true, forKey: sentinelKey)
    }
}

protocol SecItemDeleting: Sendable {
    /// Returns the raw OSStatus from `SecItemDelete`. `errSecItemNotFound` is
    /// the expected status on a clean install with no prior items — callers
    /// treat it as success.
    func delete(query: CFDictionary) -> OSStatus
}

struct SecItemDeleter: SecItemDeleting {
    func delete(query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}
