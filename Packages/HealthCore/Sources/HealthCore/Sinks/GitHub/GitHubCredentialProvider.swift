import Foundation

public protocol GitHubCredentialProvider: Sendable {
    var owner: String { get }
    var repo: String { get }
    var branch: String { get }
    var subdir: String { get }
    func accessToken() async throws -> String
    func invalidateSession() async
}

extension GitHubCredentialProvider {
    public var repositoryPath: String { "\(owner)/\(repo)" }
    public func invalidateSession() async {}
}

public struct StaticCredentialProvider: GitHubCredentialProvider {
    public let owner: String
    public let repo: String
    public let branch: String
    public let subdir: String
    private let token: String

    public init(token: String, owner: String, repo: String, branch: String, subdir: String = "") {
        self.token = token
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.subdir = subdir
    }

    public func accessToken() async throws -> String { token }
}

public actor DeviceFlowCredentialProvider: GitHubCredentialProvider {
    public nonisolated let owner: String
    public nonisolated let repo: String
    public nonisolated let branch: String
    public nonisolated let subdir: String

    private let vault: TokenVault
    private let client: GitHubDeviceFlowClient
    private let clock: @Sendable () -> Date
    private var inFlight: Task<StoredTokens, Error>?

    public init(
        vault: TokenVault,
        client: GitHubDeviceFlowClient,
        clock: @escaping @Sendable () -> Date = { Date() },
        owner: String,
        repo: String,
        branch: String,
        subdir: String = ""
    ) {
        self.vault = vault
        self.client = client
        self.clock = clock
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.subdir = subdir
    }

    /// Returns a valid access token, refreshing the stored pair if needed.
    ///
    /// Error semantics:
    /// - `GitHubAuthError.sessionExpired` — vault is empty, the refresh
    ///   token is missing, or GitHub rejected the refresh. The vault is
    ///   wiped and the user must reconnect.
    /// - Any other thrown error (e.g. `KeychainError.interactionNotAllowed`
    ///   from a locked device) is propagated as-is and the vault is
    ///   **not** cleared. Callers should treat these as retry-later.
    public func accessToken() async throws -> String {
        // Single-flight: every concurrent caller awaits the SAME task, which
        // performs the load, expiry check, and (if needed) refresh internally.
        // Because the check-and-assign below has no suspension point between
        // reading `inFlight` and writing it, two callers can never both start a
        // refresh — the one refresh uses the single-use refresh token exactly
        // once. A caller that arrives after the task cleared `inFlight` builds a
        // fresh task that reloads the vault from scratch, so it can never act on
        // a pre-refresh snapshot and re-refresh with an already-rotated token.
        let task: Task<StoredTokens, Error>
        if let existing = inFlight {
            task = existing
        } else {
            task = makeTokenTask()
            inFlight = task
        }
        do {
            let tokens = try await task.value
            if inFlight == task { inFlight = nil }
            return tokens.accessToken
        } catch {
            if inFlight == task { inFlight = nil }
            throw error
        }
    }

    public func invalidateSession() async {
        inFlight?.cancel()
        inFlight = nil
        try? await vault.clear()
    }

    private func makeTokenTask() -> Task<StoredTokens, Error> {
        let vault = self.vault
        let client = self.client
        let clock = self.clock
        return Task {
            guard let stored = try await vault.load() else {
                throw GitHubAuthError.sessionExpired
            }
            if stored.accessExpiresAt > clock().addingTimeInterval(60) {
                return stored
            }
            // GitHub Apps with token expiration disabled return tokens without a
            // refresh_token; we persist that as `nil`. Refreshing without a
            // refresh token would always fail with bad_refresh_token, then clear
            // the vault, silently forcing the user to re-auth. Treat the missing
            // refresh token as a signal that this token is non-refreshable and
            // surface session expiry directly without round-tripping to GitHub.
            guard let refreshToken = stored.refreshToken, !refreshToken.isEmpty else {
                try? await vault.clear()
                throw GitHubAuthError.sessionExpired
            }
            let pair: TokenPair
            do {
                pair = try await client.refresh(refreshToken: refreshToken)
            } catch GitHubAuthError.sessionExpired {
                try? await vault.clear()
                throw GitHubAuthError.sessionExpired
            }
            let refreshed = StoredTokens(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                accessExpiresAt: pair.accessExpiresAt,
                refreshExpiresAt: pair.refreshExpiresAt
            )
            do {
                try await vault.save(refreshed)
            } catch {
                // GitHub rotated the refresh token server-side; if we can't persist
                // the new pair, the old refresh token in the vault is already invalid.
                // Wipe the vault and force the user to reconnect rather than silently
                // racing with a doomed refresh token on the next call.
                try? await vault.clear()
                throw GitHubAuthError.sessionExpired
            }
            // Note: do NOT check Task.isCancelled here. The vault.save above
            // succeeded — tokens are valid and persisted. Cancellation at this
            // point almost certainly reflects the user dismissing the auth UI
            // sheet, not invalid tokens, and clearing the vault would force a
            // gratuitous re-auth on the next run. See pc-0we.
            return refreshed
        }
    }
}
