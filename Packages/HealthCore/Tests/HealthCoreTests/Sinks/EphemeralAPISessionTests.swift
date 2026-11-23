import XCTest
@testable import HealthCore

final class EphemeralAPISessionTests: XCTestCase {
    func test_make_returnsEphemeralConfiguredSession() {
        let session = EphemeralAPISession.make()
        defer { session.invalidateAndCancel() }

        XCTAssertEqual(
            session.configuration.requestCachePolicy,
            .reloadIgnoringLocalCacheData,
            "ephemeral API session must bypass caches so bearer-token responses are not stored on disk"
        )
        XCTAssertEqual(session.configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        XCTAssertNil(session.configuration.urlCache)
    }

    func test_make_returnsFreshInstancePerCall() {
        let a = EphemeralAPISession.make()
        defer { a.invalidateAndCancel() }
        let b = EphemeralAPISession.make()
        defer { b.invalidateAndCancel() }
        XCTAssertFalse(a === b, "callers must own their own ephemeral session")
    }

    func test_shared_isStableAndEphemerallyConfigured() {
        let session = EphemeralAPISession.shared

        XCTAssertTrue(session === EphemeralAPISession.shared, "shared must return one long-lived instance")
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(session.configuration.httpCookieAcceptPolicy, .never)
        XCTAssertFalse(session.configuration.httpShouldSetCookies)
        XCTAssertNil(session.configuration.urlCache)
    }

    func test_deviceFlowClient_defaultSession_doesNotUseSharedURLCache() {
        let client = GitHubDeviceFlowClient(clientID: "Iv1.test")

        XCTAssertNil(client.session.configuration.urlCache,
                     "token-exchange responses contain access tokens and must never hit the on-disk URLCache")
        XCTAssertEqual(client.session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }
}
