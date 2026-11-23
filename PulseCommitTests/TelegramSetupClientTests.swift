import XCTest
@testable import PulseCommit

@MainActor
final class TelegramSetupClientTests: XCTestCase {
    private final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var response = Data()
        nonisolated(unsafe) static var requests: [URLRequest] = []
        nonisolated(unsafe) static var lastBody: Data?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requests.append(request)
            Self.lastBody = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.response)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}

        private static func readBodyStream(_ stream: InputStream?) -> Data? {
            guard let stream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    private func makeClient(status: Int, json: String) -> TelegramSetupClient {
        StubProtocol.requests = []
        StubProtocol.lastBody = nil
        StubProtocol.status = status
        StubProtocol.response = Data(json.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return TelegramSetupClient(session: URLSession(configuration: configuration))
    }

    func test_defaultSessionDoesNotCacheTokenBearingUrls() {
        let session = TelegramSetupClient().session
        XCTAssertNil(session.configuration.urlCache)
        XCTAssertEqual(session.configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
    }

    func test_verifyBot_usesOnlyReadOnlyGetMeAndReturnsBotName() async throws {
        let client = makeClient(status: 200, json: #"{"ok":true,"result":{"username":"pulse_test_bot"}}"#)
        let username = try await client.verifyBot(token: "fixture-token")
        XCTAssertEqual(username, "pulse_test_bot")
        XCTAssertEqual(StubProtocol.requests.map { $0.url?.lastPathComponent }, ["getMe"])
        XCTAssertEqual(StubProtocol.requests.first?.httpMethod, "GET")
        XCTAssertNil(StubProtocol.requests.first?.httpBody)
    }

    func test_verifyBot_invalidTokenGivesActionableErrorWithoutEchoingSecret() async {
        let client = makeClient(status: 401, json: #"{"ok":false,"description":"Unauthorized fixture-token"}"#)
        do {
            _ = try await client.verifyBot(token: "fixture-token")
            XCTFail("Expected invalid token")
        } catch let error as TelegramSetupError {
            XCTAssertEqual(error, .invalidToken)
            XCTAssertTrue(error.localizedDescription.contains("token"))
            XCTAssertFalse(error.localizedDescription.contains("fixture-token"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_sendTestMessage_targetsConfiguredChatAndTopicWithFixedNonHealthText() async throws {
        let client = makeClient(status: 200, json: #"{"ok":true,"result":{"message_id":42}}"#)
        try await client.sendTestMessage(token: "fixture-token", chatID: "-1001234567890", threadID: 42)
        let request = try XCTUnwrap(StubProtocol.requests.first)
        XCTAssertEqual(StubProtocol.requests.map { $0.url?.lastPathComponent }, ["sendMessage"])
        XCTAssertEqual(request.httpMethod, "POST")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
        XCTAssertEqual(body["chat_id"] as? String, "-1001234567890")
        XCTAssertEqual(body["message_thread_id"] as? Int, 42)
        XCTAssertEqual(body["text"] as? String, TelegramSetupClient.testMessage)
        XCTAssertFalse(TelegramSetupClient.testMessage.lowercased().contains("health"))
        XCTAssertNil(body["parse_mode"])
    }

    func test_sendTestMessage_withoutTopicOmitsThreadParameter() async throws {
        let client = makeClient(status: 200, json: #"{"ok":true,"result":{"message_id":43}}"#)
        try await client.sendTestMessage(token: "fixture-token", chatID: "123456", threadID: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.lastBody)) as? [String: Any])
        XCTAssertEqual(body["chat_id"] as? String, "123456")
        XCTAssertNil(body["message_thread_id"])
    }

    func test_sendTestMessage_distinguishesChatPermissionsAndTopicErrors() async {
        let cases: [(Int, String, TelegramSetupError)] = [
            (400, #"{"ok":false,"description":"Bad Request: chat not found"}"#, .chatNotFound),
            (403, #"{"ok":false,"description":"Forbidden: bot is not a member"}"#, .botForbidden),
            (400, #"{"ok":false,"description":"Bad Request: message thread not found"}"#, .threadNotFound)
        ]
        for (status, json, expected) in cases {
            let client = makeClient(status: status, json: json)
            do {
                try await client.sendTestMessage(token: "fixture-token", chatID: "-1001234567890", threadID: 42)
                XCTFail("Expected \(expected)")
            } catch let error as TelegramSetupError {
                XCTAssertEqual(error, expected)
                XCTAssertFalse(error.localizedDescription.contains("fixture-token"))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
