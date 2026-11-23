import Foundation

/// Static configuration for the Pulse Commit GitHub App used by the Device Flow auth.
///
/// `clientID` is the production value for the `pulse-commit` GitHub App
/// (registered per `docs/operations/github-app-setup.md`). It is public by
/// design — Device Flow has no client secret. Tests mock the network
/// transport and never hit github.com.
public enum GitHubAppConfig {
    public static let clientID = "Iv23likeUxgLYkRWrv3B"
}
