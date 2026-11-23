import Foundation
import Observation
import HealthCore

public enum GitHubBranchFetcherError: Error, Equatable {
    case unauthorized
    case notFound
    case unexpected(statusCode: Int)
    case network(URLError)
}

@MainActor
@Observable
final class GitHubBranchFetcher {
    let session: URLSession

    init(session: URLSession = EphemeralAPISession.shared) {
        self.session = session
    }

    func loadBranches(owner: String, repo: String, token: String) async throws -> [String] {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/branches?per_page=100")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw GitHubBranchFetcherError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubBranchFetcherError.unexpected(statusCode: -1)
        }

        switch http.statusCode {
        case 200..<300:
            let branches = try JSONDecoder().decode([BranchDTO].self, from: data)
            return branches.map(\.name)
        case 401:
            throw GitHubBranchFetcherError.unauthorized
        case 404:
            throw GitHubBranchFetcherError.notFound
        default:
            throw GitHubBranchFetcherError.unexpected(statusCode: http.statusCode)
        }
    }

    private struct BranchDTO: Decodable {
        let name: String
    }
}
