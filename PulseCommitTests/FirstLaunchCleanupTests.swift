import XCTest
import Security
@testable import PulseCommit

final class FirstLaunchCleanupTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "FirstLaunchCleanupTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_firstLaunch_callsDeleterAndSetsSentinel() {
        let defaults = makeDefaults()
        let deleter = SpyDeleter(returning: errSecSuccess)
        let service = "FirstLaunchCleanupTests.\(UUID().uuidString)"

        FirstLaunchCleanup.runIfNeeded(defaults: defaults, service: service, deleter: deleter)

        XCTAssertEqual(deleter.calls.count, 1)
        let query = deleter.calls[0] as? [String: Any]
        XCTAssertEqual(query?[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query?[kSecAttrService as String] as? String, service)
        XCTAssertEqual(defaults.bool(forKey: FirstLaunchCleanup.sentinelKey), true)
    }

    func test_subsequentLaunch_doesNotCallDeleter() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: FirstLaunchCleanup.sentinelKey)
        let deleter = SpyDeleter(returning: errSecSuccess)

        FirstLaunchCleanup.runIfNeeded(defaults: defaults, deleter: deleter)

        XCTAssertEqual(deleter.calls.count, 0)
    }

    func test_itemNotFoundOnFirstLaunch_isToleratedAndSentinelStillSet() {
        // Clean install: there are no prior keychain items. SecItemDelete
        // returns errSecItemNotFound. Cleanup must still mark the install
        // as initialised so it doesn't run on every subsequent launch.
        let defaults = makeDefaults()
        let deleter = SpyDeleter(returning: errSecItemNotFound)

        FirstLaunchCleanup.runIfNeeded(defaults: defaults, deleter: deleter)

        XCTAssertEqual(deleter.calls.count, 1)
        XCTAssertEqual(defaults.bool(forKey: FirstLaunchCleanup.sentinelKey), true)
    }

    func test_isIdempotent_acrossMultipleCalls() {
        let defaults = makeDefaults()
        let deleter = SpyDeleter(returning: errSecSuccess)

        FirstLaunchCleanup.runIfNeeded(defaults: defaults, deleter: deleter)
        FirstLaunchCleanup.runIfNeeded(defaults: defaults, deleter: deleter)
        FirstLaunchCleanup.runIfNeeded(defaults: defaults, deleter: deleter)

        XCTAssertEqual(deleter.calls.count, 1, "delete must be called exactly once")
    }
}

private final class SpyDeleter: SecItemDeleting, @unchecked Sendable {
    private let status: OSStatus
    private let lock = NSLock()
    private var _calls: [CFDictionary] = []
    var calls: [CFDictionary] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    init(returning status: OSStatus) {
        self.status = status
    }

    func delete(query: CFDictionary) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        _calls.append(query)
        return status
    }
}
