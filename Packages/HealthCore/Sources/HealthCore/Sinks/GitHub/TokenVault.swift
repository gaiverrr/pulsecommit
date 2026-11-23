import Foundation

public struct StoredTokens: Sendable, Equatable, Codable {
    public let accessToken: String
    /// `nil` when GitHub issued a non-refreshable token (e.g. a GitHub App
    /// with "Expire user authorization tokens" turned off). Treat this as
    /// "no refresh possible" rather than an empty string sentinel — the
    /// type system enforces the distinction at every call site.
    public let refreshToken: String?
    public let accessExpiresAt: Date
    public let refreshExpiresAt: Date

    public init(accessToken: String, refreshToken: String?, accessExpiresAt: Date, refreshExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }
}

/// Secure storage for the GitHub Device-Flow access and refresh tokens.
///
/// The production implementation is Keychain-backed (`KeychainTokenVault`);
/// `InMemoryTokenVault` is provided for tests. Conformers must be
/// `Sendable` and should treat the underlying storage as the source of
/// truth — do not cache `load()` results inside a wrapper.
public protocol TokenVault: Sendable {
    /// Read the currently stored tokens, or `nil` if the user has never
    /// signed in or `clear()` was called since.
    ///
    /// - Throws: An I/O error if the backing store fails (Keychain
    ///   `errSecItemNotFound` is mapped to `nil`, not thrown).
    func load() async throws -> StoredTokens?

    /// Persist `tokens`, overwriting any existing entry atomically.
    /// - Throws: An I/O error if the backing store rejects the write.
    func save(_ tokens: StoredTokens) async throws

    /// Remove any stored tokens. Idempotent — clearing an empty vault
    /// is a no-op and must not throw.
    func clear() async throws
}

public actor InMemoryTokenVault: TokenVault {
    private var tokens: StoredTokens?

    public init(initial: StoredTokens? = nil) {
        self.tokens = initial
    }

    public func load() async throws -> StoredTokens? { tokens }

    public func save(_ tokens: StoredTokens) async throws {
        self.tokens = tokens
    }

    public func clear() async throws {
        tokens = nil
    }
}
