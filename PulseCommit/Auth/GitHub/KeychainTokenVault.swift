import Foundation
import HealthCore

public actor KeychainTokenVault: TokenVault {
    public static let storageKey = "github_stored_tokens"

    private let secrets: SecretsStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(secrets: SecretsStore) {
        self.secrets = secrets
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func load() async throws -> StoredTokens? {
        guard let raw = try await secrets.get(Self.storageKey),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        // A corrupt or schema-mismatched payload (e.g. after an app update)
        // must not soft-brick reconnect. Treat as "no tokens" and clear.
        guard let stored = try? decoder.decode(StoredTokens.self, from: data) else {
            try? await secrets.set(nil, for: Self.storageKey)
            return nil
        }
        return stored
    }

    public func save(_ tokens: StoredTokens) async throws {
        let data = try encoder.encode(tokens)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainTokenVaultError.encodingFailed
        }
        try await secrets.set(string, for: Self.storageKey)
    }

    public func clear() async throws {
        try await secrets.set(nil, for: Self.storageKey)
    }

    static func hasStoredTokens(in secrets: SecretsStore) async -> Bool {
        guard let raw = (try? await secrets.get(Self.storageKey)) ?? nil,
              let data = raw.data(using: .utf8) else {
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(StoredTokens.self, from: data)) != nil
    }
}

enum KeychainTokenVaultError: Error {
    case encodingFailed
}
