import XCTest
@testable import PulseCommit

final class GitHubBranchFetcherTests: XCTestCase {
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
    private func makeFetcher() -> GitHubBranchFetcher {
        StubProtocol.responses = [:]
        StubProtocol.lastRequest = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return GitHubBranchFetcher(session: URLSession(configuration: config))
    }

    @MainActor
    func test_defaultSession_bypassesOnDiskURLCache() {
        let fetcher = GitHubBranchFetcher()
        XCTAssertNil(fetcher.session.configuration.urlCache,
                     "bearer-token branch requests must not be persisted to the shared URLCache")
        XCTAssertEqual(fetcher.session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    @MainActor
    func test_loadBranches_parsesThreeBranches() async throws {
        let fetcher = makeFetcher()
        let body = """
        [
          {"name": "main", "commit": {"sha": "abc"}},
          {"name": "develop", "commit": {"sha": "def"}},
          {"name": "feature/x", "commit": {"sha": "ghi"}}
        ]
        """.data(using: .utf8)!
        StubProtocol.responses["/repos/octocat/hello-world/branches"] = .init(status: 200, body: body)

        let branches = try await fetcher.loadBranches(owner: "octocat", repo: "hello-world", token: "gho_test")

        XCTAssertEqual(branches, ["main", "develop", "feature/x"])
        XCTAssertEqual(StubProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer gho_test")
        XCTAssertEqual(StubProtocol.lastRequest?.url?.query, "per_page=100")
    }

    @MainActor
    func test_loadBranches_notFoundMapsTo404Error() async {
        let fetcher = makeFetcher()
        StubProtocol.responses["/repos/octocat/missing/branches"] = .init(status: 404, body: Data())
        do {
            _ = try await fetcher.loadBranches(owner: "octocat", repo: "missing", token: "t")
            XCTFail("expected to throw")
        } catch let error as GitHubBranchFetcherError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    @MainActor
    func test_loadBranches_unauthorizedMapsTo401Error() async {
        let fetcher = makeFetcher()
        StubProtocol.responses["/repos/octocat/hello-world/branches"] = .init(status: 401, body: Data())
        do {
            _ = try await fetcher.loadBranches(owner: "octocat", repo: "hello-world", token: "t")
            XCTFail("expected to throw")
        } catch let error as GitHubBranchFetcherError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
