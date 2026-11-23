import XCTest
import HealthCore
@testable import PulseCommit

final class KeychainTokenVaultTests: XCTestCase {
    private func makeVault() -> (KeychainTokenVault, KeychainSecretsStore) {
        let secrets = KeychainSecretsStore(service: "KeychainTokenVaultTests.\(UUID().uuidString)")
        return (KeychainTokenVault(secrets: secrets), secrets)
    }

    private func sampleTokens() -> StoredTokens {
        StoredTokens(
            accessToken: "gho_access_abc",
            refreshToken: "ghr_refresh_xyz",
            accessExpiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_810_000_000)
        )
    }

    func test_load_empty_returnsNil() async throws {
        let (vault, _) = makeVault()
        let loaded = try await vault.load()
        XCTAssertNil(loaded)
    }

    func test_save_thenLoad_roundTrip() async throws {
        let (vault, _) = makeVault()
        let tokens = sampleTokens()
        try await vault.save(tokens)
        let loaded = try await vault.load()
        XCTAssertEqual(loaded, tokens)
    }

    func test_save_overwritesPrevious() async throws {
        let (vault, _) = makeVault()
        try await vault.save(sampleTokens())
        let replacement = StoredTokens(
            accessToken: "gho_new",
            refreshToken: "ghr_new",
            accessExpiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_910_000_000)
        )
        try await vault.save(replacement)
        let loaded = try await vault.load()
        XCTAssertEqual(loaded, replacement)
    }

    func test_clear_removesStoredTokens() async throws {
        let (vault, _) = makeVault()
        try await vault.save(sampleTokens())
        try await vault.clear()
        let loaded = try await vault.load()
        XCTAssertNil(loaded)
    }

    func test_clear_whenEmpty_doesNotThrow() async throws {
        let (vault, _) = makeVault()
        await XCTAssertNoThrowAsync(try await vault.clear())
    }

    /// When the underlying SecretsStore.get throws KeychainError.interactionNotAllowed
    /// (locked device), the vault MUST propagate that error rather than silently
    /// returning nil. Returning nil would cause DeviceFlowCredentialProvider to
    /// throw .sessionExpired and force a re-auth despite valid stored tokens.
    func test_load_propagatesKeychainErrorWithoutClearing() async {
        let secrets = ThrowingSecretsStore(error: KeychainError.interactionNotAllowed)
        let vault = KeychainTokenVault(secrets: secrets)
        do {
            _ = try await vault.load()
            XCTFail("expected throw")
        } catch let err as KeychainError {
            XCTAssertEqual(err, .interactionNotAllowed)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        let setCallCount = await secrets.setCallCount
        XCTAssertEqual(setCallCount, 0, "vault must not call set(nil) on transient keychain error")
    }
}

private actor ThrowingSecretsStore: SecretsStore {
    private let error: Error
    private(set) var setCallCount = 0

    init(error: Error) {
        self.error = error
    }

    func get(_ key: String) async throws -> String? {
        throw error
    }

    func set(_ value: String?, for key: String) async throws {
        setCallCount += 1
    }
}

private func XCTAssertNoThrowAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
