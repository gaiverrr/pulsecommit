import Foundation
import Security

public enum WebhookConfigurationError: Error, Equatable, Sendable {
    case insecureScheme
    case missingHost
    case credentialsInURL
    case invalidHeaderName
    case reservedHeaderName
    case invalidToken
}

extension WebhookConfigurationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .insecureScheme: return "Use an https:// URL."
        case .missingHost: return "The URL has no host."
        case .credentialsInURL: return "Remove the user name and password from the URL. Use the token field instead."
        case .invalidHeaderName: return "The header name can only contain letters, digits and - _ . ! # $ % & ' * + ^ ` | ~"
        case .reservedHeaderName: return "This header is set by Pulse Commit. Choose another header name."
        case .invalidToken: return "The token can only contain visible ASCII characters, up to 4096 of them."
        }
    }
}

public struct WebhookConsentIdentity: Hashable, Codable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int?
    public let path: String
}

public struct WebhookConfiguration: Equatable, Sendable {
    public static let defaultTokenHeader = "Authorization"
    static let reservedHeaders: Set<String> = ["content-type", "content-length", "host", "idempotency-key", "x-request-id", "user-agent"]
    private static let headerNameCharacters = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    public let endpoint: URL
    public let token: String?
    public let tokenHeader: String

    public init(endpoint: URL, token: String?, tokenHeader: String = WebhookConfiguration.defaultTokenHeader) throws {
        guard endpoint.scheme?.lowercased() == "https" else { throw WebhookConfigurationError.insecureScheme }
        guard let host = endpoint.host, !host.isEmpty else { throw WebhookConfigurationError.missingHost }
        guard endpoint.user == nil, endpoint.password == nil else { throw WebhookConfigurationError.credentialsInURL }

        let header = tokenHeader.trimmingCharacters(in: .whitespaces)
        guard (1...64).contains(header.count),
              header.unicodeScalars.allSatisfy({ Self.headerNameCharacters.contains($0) }) else {
            throw WebhookConfigurationError.invalidHeaderName
        }
        guard !Self.reservedHeaders.contains(header.lowercased()) else {
            throw WebhookConfigurationError.reservedHeaderName
        }

        let trimmedToken = token?.trimmingCharacters(in: .whitespaces)
        if let trimmedToken, !trimmedToken.isEmpty {
            guard trimmedToken.count <= 4096,
                  trimmedToken.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
                throw WebhookConfigurationError.invalidToken
            }
            self.token = trimmedToken
        } else {
            self.token = nil
        }

        self.endpoint = endpoint
        self.tokenHeader = header
    }

    public var host: String { endpoint.host ?? "" }

    public var consentIdentity: WebhookConsentIdentity {
        WebhookConsentIdentity(
            scheme: endpoint.scheme?.lowercased() ?? "https",
            host: host.lowercased(),
            port: endpoint.port,
            path: endpoint.path
        )
    }

    var authorizationHeader: (name: String, value: String)? {
        guard let token else { return nil }
        let value = tokenHeader.lowercased() == "authorization" ? "Bearer \(token)" : token
        return (tokenHeader, value)
    }

    public static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = bytes.map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
