import XCTest
@testable import HealthCore

final class GitHubDeviceFlowClientStartTests: XCTestCase {
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

    func testStartDeviceFlowHappyPath() async throws {
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

        let client = GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
        let response = try await client.startDeviceFlow()

        XCTAssertEqual(response.deviceCode, "DEV1234")
        XCTAssertEqual(response.userCode, "ABCD-1234")
        XCTAssertEqual(response.expiresIn, 900)
        XCTAssertEqual(response.interval, 5)

        let captured = GitHubMockTransport.captured
        XCTAssertEqual(captured.count, 1)
        let request = try XCTUnwrap(captured.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.host, "github.com")
        XCTAssertEqual(request.url?.path, "/login/device/code")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        let bodyString = String(data: request.httpBody ?? Data(), encoding: .utf8)
        XCTAssertEqual(bodyString, "client_id=Iv1.test")
    }

    func testStartDeviceFlowHTTP500ThrowsUnexpected() async {
        GitHubMockTransport.addRoute(
            matcher: { request in
                request.url?.host == "github.com" && request.url?.path == "/login/device/code"
            },
            response: .init(statusCode: 500, body: Data("boom".utf8))
        )

        let client = GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
        do {
            _ = try await client.startDeviceFlow()
            XCTFail("expected throw")
        } catch let error as GitHubAuthError {
            // "boom" is not a JSON `{"error":...}` envelope, so the decoded
            // errorCode is nil. The raw body has been dropped at the boundary.
            XCTAssertEqual(error, .unexpected(statusCode: 500, errorCode: nil))
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testStartDeviceFlowMalformedBodyThrowsDecodingError() async {
        GitHubMockTransport.addRoute(
            matcher: { request in
                request.url?.host == "github.com" && request.url?.path == "/login/device/code"
            },
            response: .init(statusCode: 200, body: Data("not json".utf8))
        )

        let client = GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
        do {
            _ = try await client.startDeviceFlow()
            XCTFail("expected throw")
        } catch is DecodingError {
            // expected
        } catch {
            XCTFail("expected DecodingError, got: \(error)")
        }
    }

    func testStartDeviceFlowNetworkFailureWrapsURLError() async {
        NetworkFailureProtocol.failureCode = .notConnectedToInternet
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetworkFailureProtocol.self]
        let failingSession = URLSession(configuration: config)
        defer { failingSession.invalidateAndCancel() }

        let client = GitHubDeviceFlowClient(session: failingSession, clientID: "Iv1.test")
        do {
            _ = try await client.startDeviceFlow()
            XCTFail("expected throw")
        } catch let error as GitHubAuthError {
            if case .network(let urlError) = error {
                XCTAssertEqual(urlError.code, .notConnectedToInternet)
            } else {
                XCTFail("expected .network, got: \(error)")
            }
        } catch {
            XCTFail("expected GitHubAuthError, got: \(error)")
        }
    }
}

private final class NetworkFailureProtocol: URLProtocol {
    static var failureCode: URLError.Code = .notConnectedToInternet

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(NetworkFailureProtocol.failureCode))
    }

    override func stopLoading() {}
}
