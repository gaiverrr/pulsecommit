import Foundation
import Security

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
    case dataEncodingFailed
    /// `errSecInteractionNotAllowed` (-25308): the keychain item exists, but
    /// the device is in a state that does not allow decryption right now
    /// (e.g. locked-before-first-unlock). Callers MUST treat this as a
    /// transient retry-later condition — never as session-expired — because
    /// wiping the vault would force an unnecessary re-authentication.
    case interactionNotAllowed
}

/// Actor-isolated wrapper over Keychain Services. Every SecItem* call is an
/// IPC round-trip to `securityd` and can block hundreds of milliseconds under
/// contention — running it off the main actor prevents frame drops in the UI.
///
/// First-launch keychain cleanup (`FirstLaunchCleanup.runIfNeeded`) is injected
/// as a closure run inside a `Task.detached`, so the synchronous `SecItemDelete`
/// it performs executes OFF the main actor and is awaited before any
/// production `get`/`set` runs. This preserves the "cleanup before first read"
/// ordering contract without ever blocking the main thread during cold launch.
actor KeychainSecretsStore: SecretsStore {
    private let service: String
    private let firstLaunchCleanup: Task<Void, Never>

    init(
        service: String = "app.pulsecommit",
        firstLaunchCleanup: (@Sendable () -> Void)? = nil
    ) {
        self.service = service
        if let cleanup = firstLaunchCleanup {
            self.firstLaunchCleanup = Task.detached(priority: .utility) {
                cleanup()
            }
        } else {
            self.firstLaunchCleanup = Task.detached(priority: .utility) {}
        }
    }

    func get(_ key: String) async throws -> String? {
        await firstLaunchCleanup.value
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
                return nil
            }
            return string
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func set(_ value: String?, for key: String) async throws {
        await firstLaunchCleanup.value
        let query = baseQuery(for: key)

        guard let value else {
            let status = SecItemDelete(query as CFDictionary)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                return
            case errSecInteractionNotAllowed:
                throw KeychainError.interactionNotAllowed
            default:
                throw KeychainError.unexpectedStatus(status)
            }
        }

        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataEncodingFailed
        }

        // AfterFirstUnlockThisDeviceOnly (not WhenUnlocked): App Intents
        // (ExportLastDay, BackfillRange) can fire from Siri/Shortcuts while
        // the device is locked-after-first-unlock. WhenUnlocked returned
        // errSecInteractionNotAllowed in that window and silently failed export.
        // ThisDeviceOnly keeps secrets out of iCloud Keychain / backup.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            switch addStatus {
            case errSecSuccess:
                return
            case errSecInteractionNotAllowed:
                throw KeychainError.interactionNotAllowed
            default:
                throw KeychainError.unexpectedStatus(addStatus)
            }
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

}
