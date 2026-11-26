import Foundation

public enum WebhookSinkError: Error, Equatable, Sendable {
    case httpStatus(Int)
    case redirectRefused(Int)
    case transportFailure(code: Int)
    case invalidResponse
    case missingSummary
}

extension WebhookSinkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpStatus(let status):
            let base = "Endpoint returned HTTP \(status)"
            switch status {
            case 401, 403: return "\(base). Check the token."
            case 404: return "\(base). Check the URL."
            case 413: return "\(base). The export is too large for this endpoint."
            case 429: return "\(base). The endpoint is rate limiting requests."
            default: return base
            }
        case .redirectRefused(let status):
            return "Endpoint redirected (HTTP \(status)). Redirects are refused; enter the final URL."
        case .transportFailure(let code):
            return "Network error (\(code))"
        case .invalidResponse:
            return "Endpoint returned a non-HTTP response"
        case .missingSummary:
            return "This export has no summary.json to send"
        }
    }
}

public final class WebhookSink: Sink {
    public let id: String

    private let configuration: WebhookConfiguration
    private let session: URLSession
    private let minimumInterval: TimeInterval
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let authorizePayload: @Sendable () async -> Bool
    private let pacer = RequestPacer()
    private let maxAttempts = 3
    private let maxRetryAfter: UInt64 = 60

    public convenience init(
        id: String = "webhook",
        configuration: WebhookConfiguration,
        session: URLSession,
        authorizePayload: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.init(
            id: id,
            configuration: configuration,
            session: session,
            minimumInterval: 2,
            sleep: { try await Task.sleep(nanoseconds: $0) },
            authorizePayload: authorizePayload
        )
    }

    init(
        id: String = "webhook",
        configuration: WebhookConfiguration,
        session: URLSession,
        minimumInterval: TimeInterval,
        sleep: @escaping @Sendable (UInt64) async throws -> Void,
        authorizePayload: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.id = id
        self.configuration = configuration
        self.session = session
        self.minimumInterval = minimumInterval
        self.sleep = sleep
        self.authorizePayload = authorizePayload
    }

    public func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        try await deliver(snapshot: snapshot, files: files, onAttempt: nil)
    }

    public func deliver(
        snapshot: DailySnapshot,
        files: [FileEntry],
        onAttempt: AttemptHandler?
    ) async throws -> SinkResult {
        let payload = try WebhookPayload.daily(snapshot: snapshot, files: files)
        _ = try await post(
            body: payload.body,
            requestID: payload.idempotencyKey,
            appVersion: snapshot.appVersion,
            requiresConsent: true,
            onAttempt: onAttempt
        )
        return .success(reference: payload.idempotencyKey, url: nil)
    }

    public func sendTest(appVersion: String, now: Date = Date()) async throws -> Int {
        let body = try WebhookPayload.test(appVersion: appVersion, sentAt: now)
        let requestID = "pc-test-" + UUID().uuidString.lowercased().prefix(12)
        return try await post(
            body: body,
            requestID: String(requestID),
            appVersion: appVersion,
            requiresConsent: false,
            onAttempt: nil
        )
    }

    private func makeRequest(body: Data, requestID: String, appVersion: String) -> URLRequest {
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("PulseCommit/\(appVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue(requestID, forHTTPHeaderField: "Idempotency-Key")
        request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
        if let auth = configuration.authorizationHeader {
            request.setValue(auth.value, forHTTPHeaderField: auth.name)
        }
        return request
    }

    private func post(
        body: Data,
        requestID: String,
        appVersion: String,
        requiresConsent: Bool,
        onAttempt: AttemptHandler?
    ) async throws -> Int {
        let request = makeRequest(body: body, requestID: requestID, appVersion: appVersion)
        var lastError = WebhookSinkError.invalidResponse
        var reason = "starting"

        for attempt in 1...maxAttempts {
            await onAttempt?(attempt, maxAttempts, reason)
            try await pacer.wait(minimumInterval: minimumInterval, sleep: sleep)
            if requiresConsent, !(await authorizePayload()) {
                throw HealthExportAuthorizationError.consentRequired
            }

            let response: URLResponse
            do {
                (_, response) = try await session.data(for: request, delegate: RedirectBlocker())
            } catch let error as URLError {
                lastError = .transportFailure(code: error.code.rawValue)
                reason = "network error"
                if attempt < maxAttempts { try await sleep(backoff(attempt: attempt)) }
                continue
            }

            guard let http = response as? HTTPURLResponse else { throw WebhookSinkError.invalidResponse }
            let status = http.statusCode
            switch status {
            case 200..<300:
                return status
            case 300..<400:
                throw WebhookSinkError.redirectRefused(status)
            case 408, 429, 500..<600:
                lastError = .httpStatus(status)
                reason = status == 429 ? "rate limited" : "HTTP \(status)"
                if attempt < maxAttempts {
                    try await sleep(retryAfter(http) ?? backoff(attempt: attempt))
                }
            default:
                throw WebhookSinkError.httpStatus(status)
            }
        }
        throw lastError
    }

    private func backoff(attempt: Int) -> UInt64 {
        UInt64(attempt) * 1_000_000_000
    }

    private func retryAfter(_ response: HTTPURLResponse) -> UInt64? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = UInt64(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        return min(seconds, maxRetryAfter) * 1_000_000_000
    }
}

private actor RequestPacer {
    private var lastStart: ContinuousClock.Instant?

    func wait(minimumInterval: TimeInterval, sleep: @Sendable (UInt64) async throws -> Void) async throws {
        let clock = ContinuousClock()
        if minimumInterval > 0, let lastStart {
            let elapsed = clock.now - lastStart
            let required = Duration.milliseconds(Int64(minimumInterval * 1000))
            if elapsed < required {
                let remaining = required - elapsed
                let nanos = UInt64(remaining.components.seconds) * 1_000_000_000
                    + UInt64(remaining.components.attoseconds / 1_000_000_000)
                try await sleep(nanos)
            }
        }
        lastStart = clock.now
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
