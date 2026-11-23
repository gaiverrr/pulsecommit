import XCTest
@testable import HealthCore

final class GitHubMockTransportDeviceRoutesTests: XCTestCase {
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

    // MARK: - routeDeviceCode

    func testRouteDeviceCodeReturnsEncodedResponseAndCapturesRequest() async throws {
        let canned = DeviceCodeResponse(
            deviceCode: "DEV1234",
            userCode: "ABCD-1234",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: URL(string: "https://github.com/login/device?user_code=ABCD-1234")!,
            expiresIn: 900,
            interval: 5,
            expiresAt: Date().addingTimeInterval(900)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeDeviceCode(success: canned))

        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "client_id=Iv1.test".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)

        let decoded = try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
        XCTAssertEqual(decoded.deviceCode, "DEV1234")
        XCTAssertEqual(decoded.userCode, "ABCD-1234")
        XCTAssertEqual(decoded.expiresIn, 900)
        XCTAssertEqual(decoded.interval, 5)

        let captured = GitHubMockTransport.captured
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.url?.host, "github.com")
        XCTAssertEqual(captured.first?.url?.path, "/login/device/code")
        XCTAssertEqual(captured.first?.httpMethod, "POST")
        let bodyString = String(data: captured.first?.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(bodyString, "client_id=Iv1.test")
    }

    // MARK: - routeTokenPoll

    func testRouteTokenPollAdvancesThroughStages() async throws {
        let pair = TokenPair(
            accessToken: "ghu_access",
            refreshToken: "ghr_refresh",
            accessExpiresAt: Date().addingTimeInterval(28800),
            refreshExpiresAt: Date().addingTimeInterval(15897600)
        )
        GitHubMockTransport.addRoute(
            GitHubMockTransport.routeTokenPoll(stages: [.pending, .pending, .success(pair)])
        )

        var bodies: [Data] = []
        for _ in 0..<3 {
            var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            req.httpMethod = "POST"
            req.httpBody = "client_id=Iv1.test&device_code=DEV1234&grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)
            let (data, _) = try await session.data(for: req)
            bodies.append(data)
        }

        let firstObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[0]) as? [String: Any])
        XCTAssertEqual(firstObject["error"] as? String, "authorization_pending")
        let secondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: bodies[1]) as? [String: Any])
        XCTAssertEqual(secondObject["error"] as? String, "authorization_pending")
        let third = try JSONDecoder().decode(TokenPair.self, from: bodies[2])
        XCTAssertEqual(third.accessToken, "ghu_access")
        XCTAssertEqual(third.refreshToken, "ghr_refresh")

        XCTAssertEqual(GitHubMockTransport.captured.count, 3)
    }

    func testRouteTokenPollEmitsSlowDownAndDeniedAndExpired() async throws {
        GitHubMockTransport.addRoute(
            GitHubMockTransport.routeTokenPoll(stages: [.slowDown, .denied, .expired])
        )

        var errors: [String] = []
        for _ in 0..<3 {
            var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            req.httpMethod = "POST"
            req.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:device_code".data(using: .utf8)
            let (data, _) = try await session.data(for: req)
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            errors.append(obj["error"] as? String ?? "")
        }
        XCTAssertEqual(errors, ["slow_down", "access_denied", "expired_token"])
    }

    func testRouteTokenPollDoesNotMatchRefreshGrant() async throws {
        GitHubMockTransport.addRoute(
            GitHubMockTransport.routeTokenPoll(stages: [.pending])
        )
        var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        req.httpMethod = "POST"
        req.httpBody = "grant_type=refresh_token&refresh_token=ghr_old".data(using: .utf8)
        let (_, response) = try await session.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    // MARK: - routeRefresh

    func testRouteRefreshSuccessReturnsTokenPair() async throws {
        let pair = TokenPair(
            accessToken: "ghu_new",
            refreshToken: "ghr_new",
            accessExpiresAt: Date().addingTimeInterval(28800),
            refreshExpiresAt: Date().addingTimeInterval(15897600)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(pair)))

        var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        req.httpMethod = "POST"
        req.httpBody = "client_id=Iv1.test&grant_type=refresh_token&refresh_token=ghr_old".data(using: .utf8)
        let (data, response) = try await session.data(for: req)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let decoded = try JSONDecoder().decode(TokenPair.self, from: data)
        XCTAssertEqual(decoded.accessToken, "ghu_new")
        XCTAssertEqual(decoded.refreshToken, "ghr_new")
    }

    func testRouteRefreshSessionExpiredReturns401() async throws {
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.failure(.sessionExpired)))

        var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        req.httpMethod = "POST"
        req.httpBody = "grant_type=refresh_token&refresh_token=expired".data(using: .utf8)
        let (data, response) = try await session.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["error"] as? String, "bad_refresh_token")
    }

    func testRouteRefreshUnexpectedReturnsArbitraryStatus() async throws {
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.failure(.unexpected(statusCode: 503))))

        var req = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        req.httpMethod = "POST"
        req.httpBody = "grant_type=refresh_token&refresh_token=any".data(using: .utf8)
        let (_, response) = try await session.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 503)
    }

    // MARK: - host matching

    func testTransportNowMatchesGithubComHostInAdditionToApiGithubCom() async throws {
        GitHubMockTransport.addRoute(method: "GET", pathSuffix: "/ping", response: .json(["ok": true]))

        var apiReq = URLRequest(url: URL(string: "https://api.github.com/ping")!)
        apiReq.httpMethod = "GET"
        let (_, apiResp) = try await session.data(for: apiReq)
        XCTAssertEqual((apiResp as? HTTPURLResponse)?.statusCode, 200)

        var siteReq = URLRequest(url: URL(string: "https://github.com/ping")!)
        siteReq.httpMethod = "GET"
        let (_, siteResp) = try await session.data(for: siteReq)
        XCTAssertEqual((siteResp as? HTTPURLResponse)?.statusCode, 200)
    }
}
