import XCTest
@testable import HealthCore

final class GitHubAuthErrorTests: XCTestCase {
    func testEqualSimpleCases() {
        XCTAssertEqual(GitHubAuthError.sessionExpired, .sessionExpired)
        XCTAssertEqual(GitHubAuthError.userDenied, .userDenied)
        XCTAssertEqual(GitHubAuthError.codeExpired, .codeExpired)
        XCTAssertEqual(GitHubAuthError.slowDown, .slowDown)
        XCTAssertEqual(GitHubAuthError.authorizationPending, .authorizationPending)
    }

    func testDistinctCasesNotEqual() {
        XCTAssertNotEqual(GitHubAuthError.sessionExpired, .userDenied)
        XCTAssertNotEqual(GitHubAuthError.codeExpired, .slowDown)
    }

    func testNetworkEqualityByURLErrorCode() {
        let a = GitHubAuthError.network(URLError(.notConnectedToInternet))
        let b = GitHubAuthError.network(URLError(.notConnectedToInternet))
        let c = GitHubAuthError.network(URLError(.timedOut))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testUnexpectedEqualityByStatusAndErrorCode() {
        let a = GitHubAuthError.unexpected(statusCode: 401, errorCode: nil)
        let b = GitHubAuthError.unexpected(statusCode: 401, errorCode: nil)
        let c = GitHubAuthError.unexpected(statusCode: 500, errorCode: nil)
        let d = GitHubAuthError.unexpected(statusCode: 401, errorCode: "bad_verification_code")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func testErrorCodeFromDecodesEnvelope() {
        let data = Data(#"{"error":"bad_verification_code"}"#.utf8)
        XCTAssertEqual(GitHubDeviceFlowClient.errorCode(from: data), "bad_verification_code")
    }

    func testErrorCodeFromReturnsNilForNonEnvelopeBody() {
        XCTAssertNil(GitHubDeviceFlowClient.errorCode(from: Data()))
        XCTAssertNil(GitHubDeviceFlowClient.errorCode(from: Data("not json".utf8)))
        XCTAssertNil(GitHubDeviceFlowClient.errorCode(from: Data(#"{"other":"value"}"#.utf8)))
    }

    func testLocalizedErrorEveryCaseProducesNonEmptyDescription() {
        let cases: [GitHubAuthError] = [
            .sessionExpired,
            .userDenied,
            .codeExpired,
            .slowDown,
            .authorizationPending,
            .network(URLError(.notConnectedToInternet)),
            .unexpected(statusCode: 500, errorCode: "boom")
        ]
        for error in cases {
            let description = error.errorDescription
            XCTAssertNotNil(description, "missing errorDescription for \(error)")
            XCTAssertFalse(description?.isEmpty ?? true, "empty errorDescription for \(error)")
            // Regression guard for the W2 tandem: detection must not rely on
            // the raw enum-case substring leaking into the user-facing text.
            XCTAssertFalse(
                description?.contains("sessionExpired") ?? false,
                "errorDescription for \(error) must not contain the raw 'sessionExpired' substring"
            )
        }
    }

    func testLocalizedDescriptionUsesErrorDescription() {
        // Foundation maps `localizedDescription` to `errorDescription` for any
        // type that conforms to `LocalizedError`. This is what flows into
        // HistoryEntry.errorMessage via Orchestrator's
        // "sink failed: \(error.localizedDescription)".
        let error: Error = GitHubAuthError.sessionExpired
        XCTAssertEqual(
            error.localizedDescription,
            "Your GitHub session expired. Reconnect to continue."
        )
    }

    func testNetworkDescriptionUsesSafeTransportCategoryAndNumericCode() {
        XCTAssertEqual(
            GitHubAuthError.network(URLError(.notConnectedToInternet)).localizedDescription,
            "Couldn't reach GitHub: no internet connection (URL error -1009)."
        )
        XCTAssertEqual(
            GitHubAuthError.network(URLError(.timedOut)).localizedDescription,
            "Couldn't reach GitHub: request timed out (URL error -1001)."
        )
        XCTAssertEqual(
            GitHubAuthError.network(URLError(.cannotConnectToHost)).localizedDescription,
            "Couldn't reach GitHub: couldn't connect to the host (URL error -1004)."
        )
        XCTAssertEqual(
            GitHubAuthError.network(URLError(.badURL)).localizedDescription,
            "Couldn't reach GitHub (URL error -1000). Check your connection."
        )
    }

    func testUnexpectedDescriptionKeepsOnlyDocumentedCodeAndValidHTTPStatus() {
        XCTAssertEqual(
            GitHubAuthError.unexpected(statusCode: 200, errorCode: "incorrect_client_credentials").localizedDescription,
            "Unexpected response from GitHub (HTTP 200; incorrect_client_credentials)."
        )
        XCTAssertEqual(
            GitHubAuthError.unexpected(statusCode: 503, errorCode: "unsupported_grant_type").localizedDescription,
            "Unexpected response from GitHub (HTTP 503; unsupported_grant_type)."
        )
        XCTAssertEqual(
            GitHubAuthError.unexpected(statusCode: 200, errorCode: "ghr_secret https://example.com").localizedDescription,
            "Unexpected response from GitHub (HTTP 200)."
        )
        XCTAssertEqual(
            GitHubAuthError.unexpected(statusCode: -1, errorCode: "incorrect_client_credentials").localizedDescription,
            "Unexpected response from GitHub (incorrect_client_credentials)."
        )
        XCTAssertEqual(
            GitHubAuthError.unexpected(statusCode: 999, errorCode: nil).localizedDescription,
            "Unexpected response from GitHub."
        )
    }
}
