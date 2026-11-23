import Foundation

public enum GitHubAPI {
    public static let baseURL = URL(string: "https://api.github.com")!
    public static let apiVersion = "2022-11-28"
    public static let acceptHeader = "application/vnd.github+json"

    public static func getRefRequest(owner: String, repo: String, branch: String, token: String) -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/ref/heads/\(branch)")
        return makeRequest(url: url, method: "GET", token: token, body: nil)
    }

    public static func getCommitRequest(owner: String, repo: String, token: String, sha: String) -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/commits/\(sha)")
        return makeRequest(url: url, method: "GET", token: token, body: nil)
    }

    public static func createBlobRequest(owner: String, repo: String, token: String, content: Data) throws -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/blobs")
        let body = GitHubCreateBlobRequest(content: content.base64EncodedString())
        return makeRequest(url: url, method: "POST", token: token, body: try encode(body))
    }

    // https://docs.github.com/en/rest/git/trees#create-a-tree
    // `baseTree` is optional; pass `nil` for a root tree on an empty repository.
    public static func createTreeRequest(owner: String, repo: String, token: String, baseTree: String?, entries: [GitHubTreeEntry]) throws -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/trees")
        let body = GitHubCreateTreeRequest(baseTree: baseTree, tree: entries)
        return makeRequest(url: url, method: "POST", token: token, body: try encode(body))
    }

    // https://docs.github.com/en/rest/git/commits#create-a-commit
    // `parents` is optional; pass `[]` for a root commit on an empty repository.
    public static func createCommitRequest(owner: String, repo: String, token: String, message: String, tree: String, parents: [String]) throws -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/commits")
        let body = GitHubCreateCommitRequest(message: message, tree: tree, parents: parents)
        return makeRequest(url: url, method: "POST", token: token, body: try encode(body))
    }

    // https://docs.github.com/en/rest/git/refs#create-a-reference
    // Used after a root commit on an empty repository to create the branch ref.
    public static func createRefRequest(owner: String, repo: String, branch: String, token: String, sha: String) throws -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/refs")
        let body = GitHubCreateRefRequest(ref: "refs/heads/\(branch)", sha: sha)
        return makeRequest(url: url, method: "POST", token: token, body: try encode(body))
    }

    // https://docs.github.com/en/rest/repos/contents#create-or-update-file-contents
    // PUT a single file. On an empty repository this is the ONLY endpoint that
    // can produce the first commit; it atomically creates the branch, the
    // commit, and the file. The Git Data API (blobs/trees/commits) returns
    // 409 "Git Repository is empty." until at least one commit exists.
    public static func createContentsRequest(owner: String, repo: String, token: String, branch: String, path: String, contentBase64: String, message: String) throws -> URLRequest {
        let url = repoURL(owner: owner, repo: repo)
            .appendingPathComponent("contents")
            .appendingPathComponent(path)
        let body = GitHubCreateContentsRequest(message: message, content: contentBase64, branch: branch)
        return makeRequest(url: url, method: "PUT", token: token, body: try encode(body))
    }

    public static func updateRefRequest(owner: String, repo: String, branch: String, token: String, sha: String, force: Bool = false) throws -> URLRequest {
        let url = repoURL(owner: owner, repo: repo).appendingPathComponent("git/refs/heads/\(branch)")
        let body = GitHubUpdateRefRequest(sha: sha, force: force)
        return makeRequest(url: url, method: "PATCH", token: token, body: try encode(body))
    }

    private static func repoURL(owner: String, repo: String) -> URL {
        baseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(owner)
            .appendingPathComponent(repo)
    }

    private static func makeRequest(url: URL, method: String, token: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        request.setValue(apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}
