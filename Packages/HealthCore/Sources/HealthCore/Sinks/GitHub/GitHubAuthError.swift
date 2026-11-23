import Foundation

public enum GitHubAuthError: Error, Equatable, Sendable {
    case sessionExpired
    case userDenied
    case codeExpired
    case slowDown
    case authorizationPending
    case network(URLError)
    // `errorCode` is the decoded `{"error": "<code>"}` envelope value from
    // GitHub (e.g. "bad_verification_code"), if any. The raw response body is
    // dropped at the boundary in GitHubDeviceFlowClient so partial/error
    // payloads — which could conceivably include token material on a misroute
    // — are never stored on this error. The UI and History descriptions only
    // expose codes on the explicit allowlist below. See pc-xt8.
    case unexpected(statusCode: Int, errorCode: String?)

    public static func == (lhs: GitHubAuthError, rhs: GitHubAuthError) -> Bool {
        switch (lhs, rhs) {
        case (.sessionExpired, .sessionExpired),
             (.userDenied, .userDenied),
             (.codeExpired, .codeExpired),
             (.slowDown, .slowDown),
             (.authorizationPending, .authorizationPending):
            return true
        case let (.network(l), .network(r)):
            return l.code == r.code
        case let (.unexpected(ls, lc), .unexpected(rs, rc)):
            return ls == rs && lc == rc
        default:
            return false
        }
    }
}

extension GitHubAuthError: LocalizedError {
    // Mirrors the app-layer userFacingMessage (GitHubAuthError+UI.swift) so
    // `error.localizedDescription` produces readable text instead of the
    // default `Optional("HealthCore.GitHubAuthError error N.")` mirror string.
    //
    // IMPORTANT: callers must NOT detect session expiry by substring-matching
    // these strings. Use the typed `HistoryEntry.errorKind == "sessionExpired"`
    // path written by Orchestrator (see pc-1bc).
    public var errorDescription: String? {
        switch self {
        case .sessionExpired:
            return "Your GitHub session expired. Reconnect to continue."
        case .userDenied:
            return "GitHub denied the request."
        case .codeExpired:
            return "This code expired. Try again."
        case .slowDown:
            return "Slow down — retrying…"
        case .authorizationPending:
            return "Waiting for approval…"
        case .network(let error):
            let code = error.code.rawValue
            switch error.code {
            case .notConnectedToInternet:
                return "Couldn't reach GitHub: no internet connection (URL error \(code))."
            case .timedOut:
                return "Couldn't reach GitHub: request timed out (URL error \(code))."
            case .cannotFindHost, .dnsLookupFailed:
                return "Couldn't reach GitHub: couldn't find the host (URL error \(code))."
            case .cannotConnectToHost:
                return "Couldn't reach GitHub: couldn't connect to the host (URL error \(code))."
            case .networkConnectionLost:
                return "Couldn't reach GitHub: connection was lost (URL error \(code))."
            case .secureConnectionFailed,
                 .serverCertificateHasBadDate,
                 .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid,
                 .clientCertificateRejected,
                 .clientCertificateRequired:
                return "Couldn't reach GitHub: secure connection failed (URL error \(code))."
            default:
                return "Couldn't reach GitHub (URL error \(code)). Check your connection."
            }
        case .unexpected(let statusCode, let errorCode):
            let safeCode = errorCode.flatMap { Self.documentedOAuthErrorCodes.contains($0) ? $0 : nil }
            let safeStatus = (100...599).contains(statusCode) ? "HTTP \(statusCode)" : nil
            let details = [safeStatus, safeCode].compactMap { $0 }
            return details.isEmpty
                ? "Unexpected response from GitHub."
                : "Unexpected response from GitHub (\(details.joined(separator: "; ")))."
        }
    }

    // GitHub's documented GitHub App token/device-flow errors. Keep this an
    // exact allowlist: an arbitrary `error` field may contain private material.
    private static let documentedOAuthErrorCodes: Set<String> = [
        "incorrect_client_credentials",
        "bad_refresh_token",
        "unsupported_grant_type",
        "unverified_user_email",
        "authorization_pending",
        "slow_down",
        "expired_token",
        "incorrect_device_code",
        "access_denied",
        "device_flow_disabled",
        "bad_verification_code"
    ]
}
