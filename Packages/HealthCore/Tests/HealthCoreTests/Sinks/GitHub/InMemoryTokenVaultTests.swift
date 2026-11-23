import XCTest
@testable import HealthCore

final class InMemoryTokenVaultTests: XCTestCase {
    func test_loadReturnsNilWhenEmpty() async throws {
        let vault = InMemoryTokenVault()
        let loaded = try await vault.load()
        XCTAssertNil(loaded)
    }

    func test_saveThenLoadRoundTrips() async throws {
        let vault = InMemoryTokenVault()
        let tokens = StoredTokens(
            accessToken: "access-1",
            refreshToken: "refresh-1",
            accessExpiresAt: Date(timeIntervalSince1970: 1_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 2_000_000)
        )
        try await vault.save(tokens)
        let loaded = try await vault.load()
        XCTAssertEqual(loaded, tokens)
    }

    func test_clearRemovesStoredTokens() async throws {
        let tokens = StoredTokens(
            accessToken: "a",
            refreshToken: "r",
            accessExpiresAt: Date(),
            refreshExpiresAt: Date()
        )
        let vault = InMemoryTokenVault(initial: tokens)
        let pre = try await vault.load()
        XCTAssertEqual(pre, tokens)
        try await vault.clear()
        let loaded = try await vault.load()
        XCTAssertNil(loaded)
    }

    func test_saveOverwritesExistingTokens() async throws {
        let vault = InMemoryTokenVault()
        let first = StoredTokens(accessToken: "a1", refreshToken: "r1", accessExpiresAt: Date(timeIntervalSince1970: 1), refreshExpiresAt: Date(timeIntervalSince1970: 2))
        let second = StoredTokens(accessToken: "a2", refreshToken: "r2", accessExpiresAt: Date(timeIntervalSince1970: 3), refreshExpiresAt: Date(timeIntervalSince1970: 4))
        try await vault.save(first)
        try await vault.save(second)
        let loaded = try await vault.load()
        XCTAssertEqual(loaded, second)
    }
}
