import XCTest
@testable import PulseCommit

final class GitHubInstallationPickerTests: XCTestCase {
    private final class StubProtocol: URLProtocol {
        struct Response {
            let status: Int
            let body: Data
        }

        nonisolated(unsafe) static var responses: [String: Response] = [:]
        nonisolated(unsafe) static var lastRequest: URLRequest?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            StubProtocol.lastRequest = request
            let key = request.url?.path ?? ""
            guard let resp = StubProtocol.responses[key] else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: resp.status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: resp.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    @MainActor
    private func makePicker() -> GitHubInstallationPicker {
        StubProtocol.responses = [:]
        StubProtocol.lastRequest = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return GitHubInstallationPicker(session: URLSession(configuration: config))
    }

    @MainActor
    func test_defaultSession_bypassesOnDiskURLCache() {
        let picker = GitHubInstallationPicker()
        XCTAssertNil(picker.session.configuration.urlCache,
                     "bearer-token installation requests must not be persisted to the shared URLCache")
        XCTAssertEqual(picker.session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    @MainActor
    func test_loadInstallations_parsesAccountsAndIds() async throws {
        let picker = makePicker()
        let body = """
        {
          "total_count": 2,
          "installations": [
            {"id": 101, "account": {"login": "octocat"}},
            {"id": 202, "account": {"login": "acme-org"}}
          ]
        }
        """.data(using: .utf8)!
        StubProtocol.responses["/user/installations"] = .init(status: 200, body: body)

        let installations = try await picker.loadInstallations(token: "gho_test")

        XCTAssertEqual(installations.count, 2)
        XCTAssertEqual(installations[0], GitHubInstallation(id: 101, account: "octocat"))
        XCTAssertEqual(installations[1], GitHubInstallation(id: 202, account: "acme-org"))
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer gho_test")
    }

    @MainActor
    func test_loadInstallations_notFoundMapsTo404Error() async {
        let picker = makePicker()
        StubProtocol.responses["/user/installations"] = .init(status: 404, body: Data())
        do {
            _ = try await picker.loadInstallations(token: "t")
            XCTFail("expected to throw")
        } catch let error as GitHubInstallationPickerError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    @MainActor
    func test_loadInstallations_unauthorizedMapsTo401Error() async {
        let picker = makePicker()
        StubProtocol.responses["/user/installations"] = .init(status: 401, body: Data())
        do {
            _ = try await picker.loadInstallations(token: "t")
            XCTFail("expected to throw")
        } catch let error as GitHubInstallationPickerError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    @MainActor
    func test_loadRepositories_parsesFullNameAndDefaultBranch() async throws {
        let picker = makePicker()
        let body = """
        {
          "total_count": 2,
          "repositories": [
            {"full_name": "octocat/hello-world", "default_branch": "main"},
            {"full_name": "octocat/legacy", "default_branch": "master"}
          ]
        }
        """.data(using: .utf8)!
        StubProtocol.responses["/user/installations/101/repositories"] = .init(status: 200, body: body)

        let repos = try await picker.loadRepositories(installationId: 101, token: "gho_test")

        XCTAssertEqual(repos, [
            GitHubRepo(fullName: "octocat/hello-world", defaultBranch: "main"),
            GitHubRepo(fullName: "octocat/legacy", defaultBranch: "master")
        ])
        XCTAssertEqual(StubProtocol.lastRequest?.url?.path, "/user/installations/101/repositories")
    }

    @MainActor
    func test_loadRepositories_notFoundMapsTo404Error() async {
        let picker = makePicker()
        StubProtocol.responses["/user/installations/999/repositories"] = .init(status: 404, body: Data())
        do {
            _ = try await picker.loadRepositories(installationId: 999, token: "t")
            XCTFail("expected to throw")
        } catch let error as GitHubInstallationPickerError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
