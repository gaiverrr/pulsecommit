import Foundation

/// Factory for `URLSession`s used by bearer-token API traffic (GitHub OAuth +
/// REST, Telegram Bot API). Returns an ephemeral session so that:
///
/// - No on-disk URL cache retains bodies that may contain bearer tokens or
///   private health-data payloads (Telegram puts the bot token *in the URL*).
/// - No cookies are persisted across launches.
/// - Cached responses cannot be served in place of a fresh API round-trip.
///
/// Use one of these in place of `URLSession.shared` for every outbound call
/// that touches user credentials or private data.
public enum EphemeralAPISession {
    /// Long-lived process-wide instance for callers that don't manage a session
    /// lifecycle of their own (view-local fetchers, credential-provider
    /// clients). Same configuration as `make()`, never invalidated.
    public static let shared: URLSession = make()

    public static func make() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }
}
