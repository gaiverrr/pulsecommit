import Foundation
@testable import HealthCore

final class GitHubMockTransport: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
        let headers: [String: String]

        init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = ["Content-Type": "application/json"]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }

        static func json(_ object: Any, statusCode: Int = 200) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object, options: [])) ?? Data()
            return Response(statusCode: statusCode, body: data)
        }
    }

    typealias Matcher = (URLRequest) -> Bool
    typealias Responder = (URLRequest) -> Response
    typealias Route = (matcher: Matcher, responder: Responder)

    enum TokenStage {
        case pending
        case slowDown
        case success(TokenPair)
        case denied
        case expired
    }

    enum RefreshFailure: Error {
        case sessionExpired
        case unexpected(statusCode: Int)
    }

    private static let lock = NSLock()
    private static var _routes: [Route] = []
    private static var _captured: [URLRequest] = []
    private static var _isRegistered = false

    static var captured: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _captured
    }

    static func register() {
        lock.lock()
        defer { lock.unlock() }
        if !_isRegistered {
            URLProtocol.registerClass(GitHubMockTransport.self)
            _isRegistered = true
        }
        _routes.removeAll()
        _captured.removeAll()
    }

    static func unregister() {
        lock.lock()
        defer { lock.unlock() }
        if _isRegistered {
            URLProtocol.unregisterClass(GitHubMockTransport.self)
            _isRegistered = false
        }
        _routes.removeAll()
        _captured.removeAll()
    }

    static func addRoute(matcher: @escaping Matcher, response: Response) {
        addRoute(matcher: matcher, responder: { _ in response })
    }

    static func addRoute(matcher: @escaping Matcher, responder: @escaping Responder) {
        lock.lock()
        defer { lock.unlock() }
        _routes.append((matcher, responder))
    }

    static func addRoute(_ route: Route) {
        lock.lock()
        defer { lock.unlock() }
        _routes.append(route)
    }

    static func addRoute(method: String, pathSuffix: String, response: Response) {
        addRoute(matcher: matcherFor(method: method, pathSuffix: pathSuffix), response: response)
    }

    static func addRouteSequence(method: String, pathSuffix: String, responses: [Response]) {
        final class Counter { var n = 0 }
        let counter = Counter()
        addRoute(matcher: matcherFor(method: method, pathSuffix: pathSuffix), responder: { _ in
            let idx = min(counter.n, responses.count - 1)
            counter.n += 1
            return responses[idx]
        })
    }

    private static func matcherFor(method: String, pathSuffix: String) -> Matcher {
        return { request in
            guard let url = request.url else { return false }
            let methodMatches = (request.httpMethod ?? "GET").uppercased() == method.uppercased()
            return methodMatches && url.absoluteString.hasSuffix(pathSuffix)
        }
    }

    // MARK: - Device flow route helpers

    static func routeDeviceCode(success response: DeviceCodeResponse) -> Route {
        let matcher: Matcher = { request in
            guard let url = request.url else { return false }
            return (request.httpMethod ?? "GET").uppercased() == "POST"
                && url.host == "github.com"
                && url.path == "/login/device/code"
        }
        let responder: Responder = { _ in
            let body: [String: Any] = [
                "device_code": response.deviceCode,
                "user_code": response.userCode,
                "verification_uri": response.verificationURI.absoluteString,
                "verification_uri_complete": response.verificationURIComplete.absoluteString,
                "expires_in": response.expiresIn,
                "interval": response.interval
            ]
            return .json(body)
        }
        return (matcher, responder)
    }

    static func routeTokenPoll(stages: [TokenStage]) -> Route {
        let matcher: Matcher = { request in
            guard let url = request.url else { return false }
            guard (request.httpMethod ?? "GET").uppercased() == "POST",
                  url.host == "github.com",
                  url.path == "/login/oauth/access_token" else { return false }
            let body = decodeForm(request.httpBody ?? Data())
            return body["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code"
        }
        final class Counter { var n = 0 }
        let counter = Counter()
        let responder: Responder = { _ in
            let idx = min(counter.n, stages.count - 1)
            counter.n += 1
            return responseFor(stage: stages[idx])
        }
        return (matcher, responder)
    }

    static func routeRefresh(_ result: Result<TokenPair, RefreshFailure>) -> Route {
        let matcher: Matcher = { request in
            guard let url = request.url else { return false }
            guard (request.httpMethod ?? "GET").uppercased() == "POST",
                  url.host == "github.com",
                  url.path == "/login/oauth/access_token" else { return false }
            let body = decodeForm(request.httpBody ?? Data())
            return body["grant_type"] == "refresh_token"
        }
        let responder: Responder = { _ in
            switch result {
            case .success(let pair):
                return tokenPairResponse(pair)
            case .failure(.sessionExpired):
                return .json(["error": "bad_refresh_token"], statusCode: 401)
            case .failure(.unexpected(let code)):
                return Response(statusCode: code, body: Data())
            }
        }
        return (matcher, responder)
    }

    private static func responseFor(stage: TokenStage) -> Response {
        switch stage {
        case .pending:
            return .json(["error": "authorization_pending"])
        case .slowDown:
            return .json(["error": "slow_down"])
        case .denied:
            return .json(["error": "access_denied"])
        case .expired:
            return .json(["error": "expired_token"])
        case .success(let pair):
            return tokenPairResponse(pair)
        }
    }

    private static func tokenPairResponse(_ pair: TokenPair) -> Response {
        let now = Date()
        var body: [String: Any] = [
            "access_token": pair.accessToken,
            "expires_in": Int(max(0, pair.accessExpiresAt.timeIntervalSince(now))),
            "refresh_token_expires_in": Int(max(0, pair.refreshExpiresAt.timeIntervalSince(now))),
            "token_type": "bearer",
            "scope": ""
        ]
        if let refresh = pair.refreshToken {
            body["refresh_token"] = refresh
        }
        return .json(body)
    }

    private static func decodeForm(_ data: Data) -> [String: String] {
        guard let s = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for pair in s.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).removingPercentEncoding ?? String(parts[0])
            let value = String(parts[1]).removingPercentEncoding ?? String(parts[1])
            result[key] = value
        }
        return result
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return host == "api.github.com" || host == "github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let capturedRequest = normalizedRequest()
        GitHubMockTransport.lock.lock()
        GitHubMockTransport._captured.append(capturedRequest)
        let responder = GitHubMockTransport._routes.first(where: { $0.matcher(capturedRequest) })?.responder
        let response = responder?(capturedRequest)
        GitHubMockTransport.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let resolved = response ?? Response(statusCode: 404, body: Data())
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: resolved.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: resolved.headers
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: resolved.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private func normalizedRequest() -> URLRequest {
        var copy = request
        if copy.httpBody == nil, let stream = copy.httpBodyStream {
            copy.httpBody = Self.readAll(from: stream)
        }
        return copy
    }

    private static func readAll(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
