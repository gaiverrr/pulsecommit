import Foundation

final class TelegramMockTransport: URLProtocol {
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
            URLProtocol.registerClass(TelegramMockTransport.self)
            _isRegistered = true
        }
        _routes.removeAll()
        _captured.removeAll()
    }

    static func unregister() {
        lock.lock()
        defer { lock.unlock() }
        if _isRegistered {
            URLProtocol.unregisterClass(TelegramMockTransport.self)
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

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.host == "api.telegram.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        let capturedRequest = normalizedRequest()
        TelegramMockTransport.lock.lock()
        TelegramMockTransport._captured.append(capturedRequest)
        let responder = TelegramMockTransport._routes.first(where: { $0.matcher(capturedRequest) })?.responder
        let response = responder?(capturedRequest)
        TelegramMockTransport.lock.unlock()

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
