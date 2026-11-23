import Foundation
import Observation
import HealthCore

public enum GitHubInstallationPickerError: Error, Equatable {
    case unauthorized
    case notFound
    case unexpected(statusCode: Int)
    case network(URLError)
}

public struct GitHubInstallation: Sendable, Equatable, Identifiable {
    public let id: Int
    public let account: String
}

public struct GitHubRepo: Sendable, Equatable, Identifiable {
    public var id: String { fullName }
    public let fullName: String
    public let defaultBranch: String
}

@MainActor
@Observable
final class GitHubInstallationPicker {
    let session: URLSession

    init(session: URLSession = EphemeralAPISession.shared) {
        self.session = session
    }

    func loadInstallations(token: String) async throws -> [GitHubInstallation] {
        let url = URL(string: "https://api.github.com/user/installations?per_page=100")!
        let data = try await get(url: url, token: token)
        let envelope = try JSONDecoder().decode(InstallationsEnvelope.self, from: data)
        return envelope.installations.map { dto in
            GitHubInstallation(id: dto.id, account: dto.account.login)
        }
    }

    func loadRepositories(installationId: Int, token: String) async throws -> [GitHubRepo] {
        let url = URL(string: "https://api.github.com/user/installations/\(installationId)/repositories?per_page=100")!
        let data = try await get(url: url, token: token)
        let envelope = try JSONDecoder().decode(RepositoriesEnvelope.self, from: data)
        return envelope.repositories.map { dto in
            GitHubRepo(fullName: dto.fullName, defaultBranch: dto.defaultBranch)
        }
    }

    private func get(url: URL, token: String) async throws -> Data {
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
            throw GitHubInstallationPickerError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubInstallationPickerError.unexpected(statusCode: -1)
        }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw GitHubInstallationPickerError.unauthorized
        case 404:
            throw GitHubInstallationPickerError.notFound
        default:
            throw GitHubInstallationPickerError.unexpected(statusCode: http.statusCode)
        }
    }

    private struct InstallationsEnvelope: Decodable {
        let installations: [InstallationDTO]
    }

    private struct InstallationDTO: Decodable {
        let id: Int
        let account: AccountDTO
    }

    private struct AccountDTO: Decodable {
        let login: String
    }

    private struct RepositoriesEnvelope: Decodable {
        let repositories: [RepositoryDTO]
    }

    private struct RepositoryDTO: Decodable {
        let fullName: String
        let defaultBranch: String

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case defaultBranch = "default_branch"
        }
    }
}
