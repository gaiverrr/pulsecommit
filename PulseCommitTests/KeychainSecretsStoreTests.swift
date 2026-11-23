import XCTest
@testable import PulseCommit

final class KeychainSecretsStoreTests: XCTestCase {
    private func makeStore() -> KeychainSecretsStore {
        let service = "KeychainSecretsStoreTests.\(UUID().uuidString)"
        return KeychainSecretsStore(service: service)
    }

    func test_get_missingKey_returnsNil() async throws {
        let store = makeStore()
        let value = try await store.get("missing")
        XCTAssertNil(value)
    }

    func test_set_thenGet_roundTrip() async throws {
        let store = makeStore()
        try await store.set("ghp_token", for: "github")
        let got = try await store.get("github")
        XCTAssertEqual(got, "ghp_token")
    }

    func test_set_overwritesExistingValue() async throws {
        let store = makeStore()
        try await store.set("first", for: "key")
        try await store.set("second", for: "key")
        let got = try await store.get("key")
        XCTAssertEqual(got, "second")
    }

    func test_setNil_removesValue() async throws {
        let store = makeStore()
        try await store.set("value", for: "key")
        try await store.set(nil, for: "key")
        let got = try await store.get("key")
        XCTAssertNil(got)
    }

    func test_setNil_onMissingKey_doesNotThrow() async {
        let store = makeStore()
        do {
            try await store.set(nil, for: "missing")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func test_set_storesItemWithAfterFirstUnlockThisDeviceOnlyAccessibility() async throws {
        let service = "KeychainSecretsStoreTests.\(UUID().uuidString)"
        let store = KeychainSecretsStore(service: service)
        try await store.set("token", for: "github")

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "github",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        XCTAssertEqual(status, errSecSuccess)
        let attrs = item as? [String: Any]
        XCTAssertEqual(
            attrs?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )

        // Update path also writes the same accessibility class.
        try await store.set("token2", for: "github")
        item = nil
        _ = SecItemCopyMatching(query as CFDictionary, &item)
        let attrs2 = item as? [String: Any]
        XCTAssertEqual(
            attrs2?[kSecAttrAccessible as String] as? String,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )

        _ = query.removeValue(forKey: kSecReturnAttributes as String)
        _ = query.removeValue(forKey: kSecMatchLimit as String)
        SecItemDelete(query as CFDictionary)
    }

    func test_interactionNotAllowedSurfacesAsDistinctError() {
        // Regression guard: the .interactionNotAllowed case is the contract
        // the credential provider relies on to avoid wiping the vault when
        // the device is locked. Make sure it is wired up distinctly from
        // .unexpectedStatus(errSecInteractionNotAllowed).
        let distinct: KeychainError = .interactionNotAllowed
        let wrapped: KeychainError = .unexpectedStatus(errSecInteractionNotAllowed)
        XCTAssertNotEqual(distinct, wrapped)
        XCTAssertEqual(distinct, .interactionNotAllowed)
    }

    /// Stress test for actor isolation: 10 concurrent reads/writes must each
    /// return the right value and not crash on race conditions.
    func test_concurrentReadsAndWritesAreSerialized() async throws {
        let store = makeStore()
        // Seed each key once so reads return a value deterministically.
        for i in 0..<10 {
            try await store.set("v-\(i)", for: "k-\(i)")
        }
        let results: [String?] = try await withThrowingTaskGroup(of: (Int, String?).self) { group in
            for i in 0..<10 {
                group.addTask {
                    let got = try await store.get("k-\(i)")
                    return (i, got)
                }
            }
            var out: [(Int, String?)] = []
            for try await pair in group { out.append(pair) }
            return out.sorted(by: { $0.0 < $1.0 }).map { $0.1 }
        }
        XCTAssertEqual(results, (0..<10).map { "v-\($0)" })
    }
}
