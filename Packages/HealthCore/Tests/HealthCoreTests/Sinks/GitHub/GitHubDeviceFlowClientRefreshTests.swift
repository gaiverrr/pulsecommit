import XCTest
@testable import HealthCore

final class GitHubDeviceFlowClientRefreshTests: XCTestCase {
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

    func testRefreshSuccessReturnsRotatedTokens() async throws {
        let now = Date()
        let newPair = TokenPair(
            accessToken: "gho_new_access",
            refreshToken: "ghr_new_refresh",
            accessExpiresAt: now.addingTimeInterval(28_800),
            refreshExpiresAt: now.addingTimeInterval(15_811_200)
        )
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.success(newPair)))

        let client = GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
        let result = try await client.refresh(refreshToken: "ghr_old")

        XCTAssertEqual(result.accessToken, "gho_new_access")
        XCTAssertNotEqual(result.refreshToken, "ghr_old")
        XCTAssertEqual(result.refreshToken, "ghr_new_refresh")

        let captured = try XCTUnwrap(GitHubMockTransport.captured.first)
        XCTAssertEqual(captured.httpMethod, "POST")
        XCTAssertEqual(captured.url?.host, "github.com")
        XCTAssertEqual(captured.url?.path, "/login/oauth/access_token")
        let bodyString = String(data: captured.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("grant_type=refresh_token"))
        XCTAssertTrue(bodyString.contains("client_id=Iv1.test"))
        XCTAssertTrue(bodyString.contains("refresh_token=ghr_old"))
    }

    func testRefreshSessionExpiredOn401() async {
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.failure(.sessionExpired)))

        let client = GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
        do {
            _ = try await client.refresh(refreshToken: "ghr_old")
            XCTFail("expected throw")
        } catch let error as GitHubAuthError {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testRefreshUnexpectedOn500() async {
        GitHubMockTransport.addRoute(GitHubMockTransport.routeRefresh(.failure(.unexpected(statusCode: 500))))

        let client = GitHubDeviceFlowClient(session: session, clientID: "Iv1.test")
        do {
            _ = try await client.refresh(refreshToken: "ghr_old")
            XCTFail("expected throw")
        } catch let error as GitHubAuthError {
            if case .unexpected(let code, _) = error {
                XCTAssertEqual(code, 500)
            } else {
                XCTFail("expected .unexpected, got: \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}
