import Foundation

public enum TelegramSinkError: Error, Equatable, Sendable {
    case httpError(statusCode: Int, body: String?)
    case invalidResponse
    case decodingFailed
    case emptyMessage
    case apiError(description: String?, errorCode: Int?, retryAfter: Int?)
    case transportFailure(code: Int)
}

extension TelegramSinkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpError(let status, let body):
            if let body, !body.isEmpty { return "HTTP \(status): \(body)" }
            return "HTTP \(status)"
        case .invalidResponse:
            return "Telegram returned a non-HTTP response"
        case .decodingFailed:
            return "Telegram response could not be decoded"
        case .emptyMessage:
            return "Cannot send an empty message"
        case .apiError(let description, let code, let retry):
            var parts: [String] = []
            if let code { parts.append("\(code)") }
            if let description, !description.isEmpty { parts.append(description) }
            if let retry { parts.append("retry after \(retry)s") }
            return parts.isEmpty ? "Telegram API error" : parts.joined(separator: " ")
        case .transportFailure(let code):
            return "Network error (\(code))"
        }
    }
}

public final class TelegramSink: Sink {
    public let id: String

    private let credentials: TelegramCredentials
    private let session: URLSession
    private let commitURL: URL?
    private let messageChunkLimit: Int
    private let sleep: @Sendable (UInt64) async throws -> Void
    private let authorizePayload: @Sendable () async -> Bool

    public convenience init(
        id: String = "telegram",
        credentials: TelegramCredentials,
        commitURL: URL? = nil,
        // No default: forces every call site to choose a session; production
        // must pass EphemeralAPISession — the bot token is embedded in the URL.
        session: URLSession,
        messageChunkLimit: Int = 4096,
        authorizePayload: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.init(
            id: id,
            credentials: credentials,
            commitURL: commitURL,
            session: session,
            messageChunkLimit: messageChunkLimit,
            sleep: { try await Task.sleep(nanoseconds: $0) },
            authorizePayload: authorizePayload
        )
    }

    init(
        id: String = "telegram",
        credentials: TelegramCredentials,
        commitURL: URL? = nil,
        session: URLSession,
        messageChunkLimit: Int = 4096,
        sleep: @escaping @Sendable (UInt64) async throws -> Void,
        authorizePayload: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.id = id
        self.credentials = credentials
        self.session = session
        self.commitURL = commitURL
        self.messageChunkLimit = messageChunkLimit
        self.sleep = sleep
        self.authorizePayload = authorizePayload
    }

    public func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        let markdown = SummaryMarkdownSerializer().serialize(
            snapshot,
            verbosity: credentials.verbosity,
            commitURL: credentials.includeGitHubLink ? commitURL : nil,
            flavor: .telegramV2
        )
        let chunks = MarkdownV2Escaper.chunk(markdown, limit: messageChunkLimit)
        guard !chunks.isEmpty else {
            throw TelegramSinkError.emptyMessage
        }

        var lastMessageID: Int = 0
        for chunk in chunks {
            let request = try TelegramAPI.sendMessageRequest(credentials: credentials, text: chunk)
            let response = try await sendMessage(request: request)
            lastMessageID = response.result?.messageID ?? lastMessageID
        }

        let zipData = try SnapshotZipBuilder().build(files: files)
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        let filename = "pulse-commit-\(dayKey).zip"
        let caption = "JSON archive · \(files.count) file\(files.count == 1 ? "" : "s") · schema \(snapshot.schemaVersion)"
        let docRequest = TelegramAPI.sendDocumentRequest(
            credentials: credentials,
            filename: filename,
            data: zipData,
            caption: caption
        )
        let docResponse = try await sendMessage(request: docRequest)
        lastMessageID = docResponse.result?.messageID ?? lastMessageID

        let url = makeMessageURL(messageID: lastMessageID)
        return .success(reference: String(lastMessageID), url: url)
    }

    private func sendMessage(request: URLRequest) async throws -> TelegramSendResponse {
        var (data, response) = try await performRequest(request)
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let parsed = Self.parseRetryAfter(data: data) ?? 1
            let seconds = UInt64(max(0, parsed))
            let (product, overflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
            try await sleep(overflow ? UInt64.max : product)
            (data, response) = try await performRequest(request)
        }
        guard let http = response as? HTTPURLResponse else {
            throw TelegramSinkError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            // Telegram's 4xx responses carry a JSON envelope:
            //   {"ok":false,"error_code":400,"description":"Bad Request: ..."}
            // Try to surface the description as `apiError` so the full text reaches
            // History; fall back to the raw body if we can't parse.
            let parsed = Self.parseAPIError(data: data)
            if parsed.description != nil || parsed.errorCode != nil {
                throw TelegramSinkError.apiError(
                    description: parsed.description,
                    errorCode: parsed.errorCode ?? http.statusCode,
                    retryAfter: parsed.retryAfter
                )
            }
            let body = String(data: data, encoding: .utf8)
            throw TelegramSinkError.httpError(statusCode: http.statusCode, body: body)
        }
        let decoded: TelegramSendResponse
        do {
            decoded = try JSONDecoder().decode(TelegramSendResponse.self, from: data)
        } catch {
            throw TelegramSinkError.decodingFailed
        }
        guard decoded.ok, decoded.result != nil else {
            let error = Self.parseAPIError(data: data)
            throw TelegramSinkError.apiError(
                description: error.description,
                errorCode: error.errorCode,
                retryAfter: error.retryAfter
            )
        }
        return decoded
    }

    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        guard await authorizePayload() else { throw HealthExportAuthorizationError.consentRequired }
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            throw TelegramSinkError.transportFailure(code: urlError.code.rawValue)
        }
    }

    private static func parseRetryAfter(data: Data) -> Int? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let params = obj["parameters"] as? [String: Any] else { return nil }
        if let n = params["retry_after"] as? NSNumber {
            return n.intValue
        }
        return nil
    }

    private static func parseAPIError(data: Data) -> (description: String?, errorCode: Int?, retryAfter: Int?) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil, nil)
        }
        let desc = obj["description"] as? String
        let code = (obj["error_code"] as? NSNumber)?.intValue
        var retry: Int?
        if let params = obj["parameters"] as? [String: Any],
           let n = params["retry_after"] as? NSNumber {
            retry = n.intValue
        }
        return (desc, code, retry)
    }

    private func makeMessageURL(messageID: Int) -> URL? {
        let chatID = credentials.chatID
        guard chatID.hasPrefix("-100") else { return nil }
        let stripped = String(chatID.dropFirst(4))
        return URL(string: "https://t.me/c/\(stripped)/\(messageID)")
    }
}

struct TelegramSendResponse: Decodable {
    let ok: Bool
    let result: Result?

    struct Result: Decodable {
        let messageID: Int

        enum CodingKeys: String, CodingKey {
            case messageID = "message_id"
        }
    }
}
