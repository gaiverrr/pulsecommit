import Foundation

final class WebhookMockTransport: URLProtocol {
    struct Response {
        let statusCode: Int
        let body: Data
        let headers: [String: String]

        init(statusCode: Int = 200, body: Data = Data(), headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }
    }

    enum Outcome {
        case response(Response)
        case failure(URLError.Code)
    }

    static let hosts: Set<String> = ["hooks.example.com", "elsewhere.example.net"]

    private static let lock = NSLock()
    private static var _outcomes: [Outcome] = []
    private static var _captured: [URLRequest] = []

    static var captured: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _captured
    }

    static func reset(_ outcomes: [Outcome]) {
        lock.lock()
        defer { lock.unlock() }
        _outcomes = outcomes
        _captured = []
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WebhookMockTransport.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return hosts.contains(host)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        var copy = request
        if copy.httpBody == nil, let stream = copy.httpBodyStream {
            copy.httpBody = Self.readAll(from: stream)
        }
        Self.lock.lock()
        Self._captured.append(copy)
        let outcome = Self._outcomes.isEmpty ? .response(Response(statusCode: 404)) : Self._outcomes.removeFirst()
        Self.lock.unlock()

        switch outcome {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .response(let resolved):
            if (300..<400).contains(resolved.statusCode),
               let location = resolved.headers["Location"],
               let target = URL(string: location) {
                let redirect = HTTPURLResponse(url: request.url!, statusCode: resolved.statusCode, httpVersion: "HTTP/1.1", headerFields: resolved.headers)!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: redirect)
            }
            let http = HTTPURLResponse(
                url: request.url!,
                statusCode: resolved.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: resolved.headers
            )!
            client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: resolved.body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private static func readAll(from stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: 4096)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
