import Foundation

public struct DeviceCodeResponse: Equatable, Sendable, Decodable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURI: URL
    public let verificationURIComplete: URL
    public let expiresIn: Int
    public let interval: Int
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }

    public init(
        deviceCode: String,
        userCode: String,
        verificationURI: URL,
        verificationURIComplete: URL,
        expiresIn: Int,
        interval: Int,
        expiresAt: Date
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.verificationURIComplete = verificationURIComplete
        self.expiresIn = expiresIn
        self.interval = interval
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceCode = try c.decode(String.self, forKey: .deviceCode)
        self.userCode = try c.decode(String.self, forKey: .userCode)
        self.verificationURI = try c.decode(URL.self, forKey: .verificationURI)
        self.expiresIn = try c.decode(Int.self, forKey: .expiresIn)
        self.interval = try c.decode(Int.self, forKey: .interval)
        self.expiresAt = Date().addingTimeInterval(TimeInterval(self.expiresIn))

        // GitHub's device-flow response does NOT include `verification_uri_complete`
        // (it's an optional RFC 8628 field). Accept it if present, otherwise
        // synthesise from `verification_uri` + `?user_code=XXXX-XXXX` so the user
        // can tap one link that pre-fills the code in their browser.
        if let provided = try c.decodeIfPresent(URL.self, forKey: .verificationURIComplete) {
            self.verificationURIComplete = provided
        } else if var components = URLComponents(url: self.verificationURI, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "user_code", value: self.userCode))
            components.queryItems = items
            self.verificationURIComplete = components.url ?? self.verificationURI
        } else {
            self.verificationURIComplete = self.verificationURI
        }
    }
}

public struct TokenPair: Equatable, Sendable, Decodable {
    public let accessToken: String
    /// `nil` when GitHub did not return a `refresh_token` (GitHub Apps with
    /// token expiration disabled). Use the optional throughout the pipeline
    /// instead of an empty-string sentinel.
    public let refreshToken: String?
    public let accessExpiresAt: Date
    public let refreshExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case refreshTokenExpiresIn = "refresh_token_expires_in"
    }

    public init(
        accessToken: String,
        refreshToken: String?,
        accessExpiresAt: Date,
        refreshExpiresAt: Date
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessExpiresAt = accessExpiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try c.decode(String.self, forKey: .accessToken)

        // GitHub Apps with "Expire user authorization tokens" turned OFF respond
        // with just {access_token, scope, token_type} — no refresh_token, no
        // expires_in. Treat that as a long-lived (non-expiring) token rather
        // than throwing, otherwise the polling loop bubbles `.unexpected` and
        // the UI never transitions out of Disconnected after a successful
        // browser approval.
        self.refreshToken = try c.decodeIfPresent(String.self, forKey: .refreshToken)

        let now = Date()
        if let expiresIn = try c.decodeIfPresent(TimeInterval.self, forKey: .expiresIn) {
            self.accessExpiresAt = now.addingTimeInterval(expiresIn)
        } else {
            self.accessExpiresAt = .distantFuture
        }
        if let refreshExpiresIn = try c.decodeIfPresent(TimeInterval.self, forKey: .refreshTokenExpiresIn) {
            self.refreshExpiresAt = now.addingTimeInterval(refreshExpiresIn)
        } else {
            self.refreshExpiresAt = self.accessExpiresAt
        }
    }
}

public enum PollOutcome: Equatable, Sendable {
    case success(TokenPair)
    case pending
    case slowDown
    case codeExpired
    case userDenied

    /// Maps the `error` string from GitHub's device-code token endpoint to a
    /// `PollOutcome`. Returns `nil` for unrecognized error codes.
    public static func from(errorCode: String) -> PollOutcome? {
        switch errorCode {
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown
        case "expired_token": return .codeExpired
        case "access_denied": return .userDenied
        default: return nil
        }
    }
}
