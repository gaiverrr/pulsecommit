import Foundation

public struct GitHubDeviceFlowClient: Sendable {
    public let session: URLSession
    public let clientID: String
    public let now: @Sendable () -> Date
    public let sleep: @Sendable (TimeInterval) async throws -> Void

    public init(
        session: URLSession = EphemeralAPISession.shared,
        clientID: String,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.session = session
        self.clientID = clientID
        self.now = now
        self.sleep = sleep
    }

    public func startDeviceFlow() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(["client_id": clientID])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw GitHubAuthError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubAuthError.unexpected(statusCode: -1, errorCode: Self.errorCode(from: data))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.unexpected(statusCode: http.statusCode, errorCode: Self.errorCode(from: data))
        }
        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    public func pollForToken(
        deviceCode: String,
        interval: Int,
        expiresAt: Date
    ) async throws -> TokenPair {
        var currentInterval = TimeInterval(max(1, interval))

        while true {
            if now() >= expiresAt {
                throw GitHubAuthError.codeExpired
            }

            let outcome = try await pollOnce(deviceCode: deviceCode)
            switch outcome {
            case .success(let pair):
                return pair
            case .pending:
                try await sleep(currentInterval)
            case .slowDown:
                currentInterval += 5
                try await sleep(currentInterval)
            case .codeExpired:
                throw GitHubAuthError.codeExpired
            case .userDenied:
                throw GitHubAuthError.userDenied
            }
        }
    }

    public func refresh(refreshToken: String) async throws -> TokenPair {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw GitHubAuthError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubAuthError.unexpected(statusCode: -1, errorCode: Self.errorCode(from: data))
        }

        if http.statusCode == 401 {
            throw GitHubAuthError.sessionExpired
        }

        let decoder = JSONDecoder()
        if (200..<300).contains(http.statusCode) {
            if let pair = try? decoder.decode(TokenPair.self, from: data) {
                return pair
            }
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                if envelope.error == "bad_refresh_token" {
                    throw GitHubAuthError.sessionExpired
                }
                // 200 with an unrecognized error envelope: keep only the code (no body).
                throw GitHubAuthError.unexpected(statusCode: http.statusCode, errorCode: envelope.error)
            }
            // 200 but neither TokenPair nor error envelope: the body may contain
            // partial token material — drop it to avoid leaking secrets via logs
            // or `String(describing:)`.
            throw GitHubAuthError.unexpected(statusCode: http.statusCode, errorCode: nil)
        }

        throw GitHubAuthError.unexpected(statusCode: http.statusCode, errorCode: Self.errorCode(from: data))
    }

    private func pollOnce(deviceCode: String) async throws -> PollOutcome {
        var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            throw GitHubAuthError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw GitHubAuthError.unexpected(statusCode: -1, errorCode: Self.errorCode(from: data))
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.unexpected(statusCode: http.statusCode, errorCode: Self.errorCode(from: data))
        }

        let decoder = JSONDecoder()
        if let pair = try? decoder.decode(TokenPair.self, from: data) {
            return .success(pair)
        }
        if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data),
           let outcome = PollOutcome.from(errorCode: envelope.error) {
            return outcome
        }
        // Unrecognized envelope — keep just the code if present, drop the body.
        throw GitHubAuthError.unexpected(
            statusCode: http.statusCode,
            errorCode: (try? decoder.decode(ErrorEnvelope.self, from: data))?.error
        )
    }

    private struct ErrorEnvelope: Decodable {
        let error: String
    }

    /// Decodes the `{"error": "<code>"}` envelope and returns just the code,
    /// or `nil` if the body isn't shaped like an envelope. Used at every
    /// throw site so raw response bytes never reach `GitHubAuthError`.
    static func errorCode(from data: Data) -> String? {
        (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error
    }

    static func formEncode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        let joined = params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
        return joined.data(using: .utf8) ?? Data()
    }
}
