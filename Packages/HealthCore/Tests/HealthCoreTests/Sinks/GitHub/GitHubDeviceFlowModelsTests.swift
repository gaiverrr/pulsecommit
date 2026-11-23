import XCTest
@testable import HealthCore

final class GitHubDeviceFlowModelsTests: XCTestCase {
    func testDeviceCodeResponseDecodesSnakeCase() throws {
        let json = """
        {
          "device_code": "3584d83530557fdd1f46af8289938c8ef79f9dc5",
          "user_code": "WDJB-MJHT",
          "verification_uri": "https://github.com/login/device",
          "verification_uri_complete": "https://github.com/login/device?user_code=WDJB-MJHT",
          "expires_in": 900,
          "interval": 5
        }
        """.data(using: .utf8)!

        let before = Date()
        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: json)
        let after = Date()

        XCTAssertEqual(response.deviceCode, "3584d83530557fdd1f46af8289938c8ef79f9dc5")
        XCTAssertEqual(response.userCode, "WDJB-MJHT")
        XCTAssertEqual(response.verificationURI, URL(string: "https://github.com/login/device"))
        XCTAssertEqual(
            response.verificationURIComplete,
            URL(string: "https://github.com/login/device?user_code=WDJB-MJHT")
        )
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertEqual(response.interval, 5)

        let lowerBound = before.addingTimeInterval(900)
        let upperBound = after.addingTimeInterval(900)
        XCTAssertGreaterThanOrEqual(response.expiresAt, lowerBound)
        XCTAssertLessThanOrEqual(response.expiresAt, upperBound)
    }

    func testDeviceCodeResponseSynthesisesVerificationURIComplete() throws {
        // GitHub's production device-flow response omits `verification_uri_complete`;
        // we must synthesise it from `verification_uri` + `?user_code=`.
        let json = """
        {
          "device_code": "ed9fa0c3de95d600421ce9efbaa0ea728ea9be43",
          "user_code": "A931-0F0C",
          "verification_uri": "https://github.com/login/device",
          "expires_in": 899,
          "interval": 5
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(DeviceCodeResponse.self, from: json)

        XCTAssertEqual(response.userCode, "A931-0F0C")
        XCTAssertEqual(response.verificationURI, URL(string: "https://github.com/login/device"))
        XCTAssertEqual(
            response.verificationURIComplete,
            URL(string: "https://github.com/login/device?user_code=A931-0F0C")
        )
    }

    func testTokenPairDecodesSnakeCaseAndComputesExpiry() throws {
        let json = """
        {
          "access_token": "ghu_access",
          "refresh_token": "ghr_refresh",
          "expires_in": 28800,
          "refresh_token_expires_in": 15897600,
          "token_type": "bearer",
          "scope": ""
        }
        """.data(using: .utf8)!

        let before = Date()
        let pair = try JSONDecoder().decode(TokenPair.self, from: json)
        let after = Date()

        XCTAssertEqual(pair.accessToken, "ghu_access")
        XCTAssertEqual(pair.refreshToken, "ghr_refresh")
        XCTAssertGreaterThanOrEqual(pair.accessExpiresAt, before.addingTimeInterval(28800))
        XCTAssertLessThanOrEqual(pair.accessExpiresAt, after.addingTimeInterval(28800))
        XCTAssertGreaterThanOrEqual(pair.refreshExpiresAt, before.addingTimeInterval(15897600))
        XCTAssertLessThanOrEqual(pair.refreshExpiresAt, after.addingTimeInterval(15897600))
    }

    func testTokenPairDecodesGitHubAppWithoutTokenExpiration() throws {
        // When a GitHub App has "Expire user authorization tokens" turned OFF,
        // the token endpoint returns ONLY {access_token, scope, token_type} —
        // no expires_in, no refresh_token, no refresh_token_expires_in.
        // The decoder must accept this shape and synthesise long-lived expiries
        // so the device-flow polling loop returns a valid TokenPair instead of
        // silently throwing `.unexpected` and leaving the UI on Disconnected.
        let json = """
        {
          "access_token": "ghu_no_expiry_token",
          "scope": "",
          "token_type": "bearer"
        }
        """.data(using: .utf8)!

        let before = Date()
        let pair = try JSONDecoder().decode(TokenPair.self, from: json)
        let after = Date()

        XCTAssertEqual(pair.accessToken, "ghu_no_expiry_token")
        XCTAssertNil(pair.refreshToken, "absent refresh_token must decode to nil, not empty string")
        // Long-lived: at least a decade from now.
        XCTAssertGreaterThan(pair.accessExpiresAt, before.addingTimeInterval(10 * 365 * 24 * 3600))
        XCTAssertEqual(pair.refreshExpiresAt, pair.accessExpiresAt)
        _ = after
    }

    func testStoredTokensRoundTripsNilRefreshToken() throws {
        let original = StoredTokens(
            accessToken: "ghu_a",
            refreshToken: nil,
            accessExpiresAt: Date(timeIntervalSince1970: 1_700_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredTokens.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.refreshToken)
    }

    func testStoredTokensDecodesLegacyPayloadWithoutRefreshTokenKey() throws {
        // A pre-pc-74u payload persisted without the refresh_token key at all
        // (or with explicit null) must decode to nil rather than failing —
        // otherwise an upgraded install would silently log the user out.
        let json = """
        {
          "accessToken": "ghu_legacy",
          "accessExpiresAt": "2026-01-01T00:00:00Z",
          "refreshExpiresAt": "2026-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StoredTokens.self, from: json)
        XCTAssertEqual(decoded.accessToken, "ghu_legacy")
        XCTAssertNil(decoded.refreshToken)
    }

    func testPollOutcomeMapsServerErrorCodes() {
        XCTAssertEqual(PollOutcome.from(errorCode: "authorization_pending"), .pending)
        XCTAssertEqual(PollOutcome.from(errorCode: "slow_down"), .slowDown)
        XCTAssertEqual(PollOutcome.from(errorCode: "expired_token"), .codeExpired)
        XCTAssertEqual(PollOutcome.from(errorCode: "access_denied"), .userDenied)
        XCTAssertNil(PollOutcome.from(errorCode: "unknown_error"))
    }

    func testPollOutcomeSuccessEquality() {
        let pair = TokenPair(
            accessToken: "a",
            refreshToken: "r",
            accessExpiresAt: Date(timeIntervalSince1970: 1),
            refreshExpiresAt: Date(timeIntervalSince1970: 2)
        )
        XCTAssertEqual(PollOutcome.success(pair), PollOutcome.success(pair))
        XCTAssertNotEqual(PollOutcome.success(pair), .pending)
    }
}
