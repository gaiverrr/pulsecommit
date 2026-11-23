import XCTest
@testable import HealthCore

final class GitHubAPITests: XCTestCase {
    private let owner = "alice"
    private let repo = "health"
    private let branch = "main"
    private let token = "ghp_test"

    private func assertCommonHeaders(_ request: URLRequest, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_test", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json", file: file, line: line)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28", file: file, line: line)
    }

    func testGetRefRequest() {
        let request = GitHubAPI.getRefRequest(owner: owner, repo: repo, branch: branch, token: token)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/alice/health/git/ref/heads/main")
        assertCommonHeaders(request)
        XCTAssertNil(request.httpBody)
    }

    func testCreateBlobRequest() throws {
        let content = "hello".data(using: .utf8)!
        let request = try GitHubAPI.createBlobRequest(owner: owner, repo: repo, token: token, content: content)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/alice/health/git/blobs")
        assertCommonHeaders(request)

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(GitHubCreateBlobRequest.self, from: body)
        XCTAssertEqual(decoded.encoding, "base64")
        XCTAssertEqual(decoded.content, content.base64EncodedString())
    }

    func testCreateTreeRequest() throws {
        let entries = [
            GitHubTreeEntry(path: "2026-05-14/summary.json", sha: "blobsha1"),
            GitHubTreeEntry(path: "2026-05-14/summary.md", sha: "blobsha2")
        ]
        let request = try GitHubAPI.createTreeRequest(owner: owner, repo: repo, token: token, baseTree: "parent123", entries: entries)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/alice/health/git/trees")
        assertCommonHeaders(request)

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(GitHubCreateTreeRequest.self, from: body)
        XCTAssertEqual(decoded.baseTree, "parent123")
        XCTAssertEqual(decoded.tree.count, 2)
        XCTAssertEqual(decoded.tree[0].path, "2026-05-14/summary.json")
        XCTAssertEqual(decoded.tree[0].mode, "100644")
        XCTAssertEqual(decoded.tree[0].type, "blob")
        XCTAssertEqual(decoded.tree[0].sha, "blobsha1")
    }

    func testCreateCommitRequest() throws {
        let request = try GitHubAPI.createCommitRequest(
            owner: owner,
            repo: repo,
            token: token,
            message: "chore: pulse 2026-05-14",
            tree: "treesha",
            parents: ["parent123"]
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/alice/health/git/commits")
        assertCommonHeaders(request)

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(GitHubCreateCommitRequest.self, from: body)
        XCTAssertEqual(decoded.message, "chore: pulse 2026-05-14")
        XCTAssertEqual(decoded.tree, "treesha")
        XCTAssertEqual(decoded.parents, ["parent123"])
    }

    func testUpdateRefRequest() throws {
        let request = try GitHubAPI.updateRefRequest(owner: owner, repo: repo, branch: branch, token: token, sha: "newcommitsha")
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/alice/health/git/refs/heads/main")
        assertCommonHeaders(request)

        let body = try XCTUnwrap(request.httpBody)
        let decoded = try JSONDecoder().decode(GitHubUpdateRefRequest.self, from: body)
        XCTAssertEqual(decoded.sha, "newcommitsha")
        XCTAssertFalse(decoded.force)
    }
}
