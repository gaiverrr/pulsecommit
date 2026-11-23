import XCTest
@testable import HealthCore

final class GitHubDeviceFlowClientPollTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        GitHubMockTransport.register()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [GitHubMockTransport.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        GitHubMockTransport.unregister()
        super.tearDown()
    }

    private func makeTokenPair() -> TokenPair {
        // Pinned base so expiry values never depend on test wall-clock.
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        return TokenPair(
            accessToken: "gho_access",
            refreshToken: "ghr_refresh",
            accessExpiresAt: base.addingTimeInterval(8 * 3600),
            refreshExpiresAt: base.addingTimeInterval(180 * 24 * 3600)
        )
    }

    func testPollSuccessFirstTry() async throws {
        let pair = makeTokenPair()
        GitHubMockTransport.addRoute(GitHubMockTransport.routeTokenPoll(stages: [.success(pair)]))

        let recorder = SleepRecorder()
        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in await recorder.append(seconds) }
        )

        let got = try await client.pollForToken(
            deviceCode: "DEV123",
            interval: 5,
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(got.accessToken, pair.accessToken)
        XCTAssertEqual(got.refreshToken, pair.refreshToken)
        let captured = GitHubMockTransport.captured
        XCTAssertEqual(captured.count, 1)
        let body = String(data: captured[0].httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("device_code=DEV123"))
        XCTAssertTrue(body.contains("client_id=Iv1.test"))
        XCTAssertTrue(body.contains("grant_type=urn:ietf:params:oauth:grant-type:device_code"), "body was: \(body)")
        let sleeps = await recorder.values
        XCTAssertEqual(sleeps, [])
    }

    func testPollPendingThenSuccess() async throws {
        let pair = makeTokenPair()
        GitHubMockTransport.addRoute(
            GitHubMockTransport.routeTokenPoll(stages: [.pending, .pending, .success(pair)])
        )

        let recorder = SleepRecorder()
        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in await recorder.append(seconds) }
        )

        let got = try await client.pollForToken(
            deviceCode: "DEV",
            interval: 5,
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(got.accessToken, pair.accessToken)
        let sleeps = await recorder.values
        XCTAssertEqual(sleeps, [5, 5])
        XCTAssertEqual(GitHubMockTransport.captured.count, 3)
    }

    func testPollSlowDownIncreasesInterval() async throws {
        let pair = makeTokenPair()
        GitHubMockTransport.addRoute(
            GitHubMockTransport.routeTokenPoll(stages: [.slowDown, .pending, .success(pair)])
        )

        let recorder = SleepRecorder()
        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in await recorder.append(seconds) }
        )

        _ = try await client.pollForToken(
            deviceCode: "DEV",
            interval: 5,
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )

        let sleeps = await recorder.values
        XCTAssertEqual(sleeps, [10, 10])
    }

    func testPollSucceedsWhenGitHubAppHasNoTokenExpiration() async throws {
        // Reproduces Bug #1: GitHub Apps with "Expire user authorization tokens"
        // disabled respond to the token-poll endpoint with HTTP 200 and a body
        // containing only {access_token, scope, token_type} — no refresh_token,
        // no expires_in. Polling must recognise this as success and return the
        // TokenPair, NOT throw `.unexpected` (which left the UI Disconnected).
        let matcher: GitHubMockTransport.Matcher = { request in
            guard let url = request.url else { return false }
            return (request.httpMethod ?? "GET").uppercased() == "POST"
                && url.host == "github.com"
                && url.path == "/login/oauth/access_token"
        }
        let responder: GitHubMockTransport.Responder = { _ in
            .json([
                "access_token": "ghu_no_expiry",
                "scope": "",
                "token_type": "bearer"
            ])
        }
        GitHubMockTransport.addRoute((matcher, responder))

        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { _ in }
        )

        let got = try await client.pollForToken(
            deviceCode: "DEV",
            interval: 5,
            expiresAt: Date(timeIntervalSince1970: 2_000)
        )

        XCTAssertEqual(got.accessToken, "ghu_no_expiry")
        XCTAssertNil(got.refreshToken)
    }

    func testPollCodeExpiredWhenClockAdvancesPastExpiresAt() async {
        let recorder = SleepRecorder()
        let clockState = ClockState(start: Date(timeIntervalSince1970: 1_000))
        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { clockState.current },
            sleep: { seconds in
                await recorder.append(seconds)
                clockState.advance(by: seconds)
            }
        )

        GitHubMockTransport.addRoute(
            GitHubMockTransport.routeTokenPoll(stages: [.pending, .pending, .pending])
        )

        do {
            _ = try await client.pollForToken(
                deviceCode: "DEV",
                interval: 5,
                expiresAt: Date(timeIntervalSince1970: 1_006)
            )
            XCTFail("expected codeExpired")
        } catch let error as GitHubAuthError {
            XCTAssertEqual(error, .codeExpired)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testPollServerExpiredTokenThrowsCodeExpired() async {
        GitHubMockTransport.addRoute(GitHubMockTransport.routeTokenPoll(stages: [.expired]))
        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { _ in }
        )
        do {
            _ = try await client.pollForToken(
                deviceCode: "DEV",
                interval: 5,
                expiresAt: Date(timeIntervalSince1970: 2_000)
            )
            XCTFail("expected codeExpired")
        } catch let error as GitHubAuthError {
            XCTAssertEqual(error, .codeExpired)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testPollUserDeniedThrowsUserDenied() async {
        GitHubMockTransport.addRoute(GitHubMockTransport.routeTokenPoll(stages: [.denied]))
        let client = GitHubDeviceFlowClient(
            session: session,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { _ in }
        )
        do {
            _ = try await client.pollForToken(
                deviceCode: "DEV",
                interval: 5,
                expiresAt: Date(timeIntervalSince1970: 2_000)
            )
            XCTFail("expected userDenied")
        } catch let error as GitHubAuthError {
            XCTAssertEqual(error, .userDenied)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    func testPollNetworkFailureWrapsURLError() async {
        PollNetworkFailureProtocol.failureCode = .notConnectedToInternet
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PollNetworkFailureProtocol.self]
        let failingSession = URLSession(configuration: config)
        defer { failingSession.invalidateAndCancel() }

        let client = GitHubDeviceFlowClient(
            session: failingSession,
            clientID: "Iv1.test",
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { _ in }
        )

        do {
            _ = try await client.pollForToken(
                deviceCode: "DEV",
                interval: 5,
                expiresAt: Date(timeIntervalSince1970: 2_000)
            )
            XCTFail("expected throw")
        } catch let error as GitHubAuthError {
            if case .network(let urlError) = error {
                XCTAssertEqual(urlError.code, .notConnectedToInternet)
            } else {
                XCTFail("expected .network, got: \(error)")
            }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}

private actor SleepRecorder {
    private(set) var values: [TimeInterval] = []
    func append(_ value: TimeInterval) { values.append(value) }
}

private final class ClockState: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(start: Date) { self._now = start }

    var current: Date {
        lock.lock(); defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        _now = _now.addingTimeInterval(seconds)
    }
}

private final class PollNetworkFailureProtocol: URLProtocol {
    static var failureCode: URLError.Code = .notConnectedToInternet

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(PollNetworkFailureProtocol.failureCode))
    }

    override func stopLoading() {}
}
