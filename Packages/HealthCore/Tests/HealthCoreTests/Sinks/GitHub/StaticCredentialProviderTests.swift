import XCTest
@testable import HealthCore

final class StaticCredentialProviderTests: XCTestCase {
    func testReturnsTokenUnchanged() async throws {
        let provider = StaticCredentialProvider(
            token: "ghp_test_token",
            owner: "octocat",
            repo: "hello-world",
            branch: "main",
            subdir: "data"
        )
        let token = try await provider.accessToken()
        XCTAssertEqual(token, "ghp_test_token")
    }

    func testExposesRepoCoords() {
        let provider = StaticCredentialProvider(
            token: "t",
            owner: "octocat",
            repo: "hello-world",
            branch: "main",
            subdir: "sub"
        )
        XCTAssertEqual(provider.owner, "octocat")
        XCTAssertEqual(provider.repo, "hello-world")
        XCTAssertEqual(provider.branch, "main")
        XCTAssertEqual(provider.subdir, "sub")
        XCTAssertEqual(provider.repositoryPath, "octocat/hello-world")
    }

    func testDefaultSubdirIsEmpty() {
        let provider = StaticCredentialProvider(
            token: "t",
            owner: "o",
            repo: "r",
            branch: "main"
        )
        XCTAssertEqual(provider.subdir, "")
    }

    func testConformsToProtocol() async throws {
        let provider: any GitHubCredentialProvider = StaticCredentialProvider(
            token: "abc",
            owner: "o",
            repo: "r",
            branch: "main"
        )
        let token = try await provider.accessToken()
        XCTAssertEqual(token, "abc")
    }
}
