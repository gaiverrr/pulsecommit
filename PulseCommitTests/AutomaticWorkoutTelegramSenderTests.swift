import XCTest
import HealthCore
@testable import PulseCommit

final class AutomaticWorkoutTelegramSenderTests: XCTestCase {
    private final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var data = Data()
        nonisolated(unsafe) static var request: URLRequest?
        nonisolated(unsafe) static var body: Data?
        nonisolated(unsafe) static var failure: Error?
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.request = request
            Self.body = request.httpBody ?? Self.readBodyStream(request.httpBodyStream)
            if let failure = Self.failure {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}

        private static func readBodyStream(_ stream: InputStream?) -> Data? {
            guard let stream else { return nil }
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1_024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    func test_sendPostsOneMarkdownMessageToExactTopicWithoutDocumentOrDailyPayload() async throws {
        let session = makeSession(status: 200, json: #"{"ok":true,"result":{"message_id":77}}"#)
        let sender = makeSender(session: session)

        let result = await sender.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")

        XCTAssertEqual(result, .delivered(messageID: 77))
        let request = try XCTUnwrap(StubProtocol.request)
        XCTAssertEqual(request.url?.lastPathComponent, "sendMessage")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubProtocol.body)) as? [String: Any])
        XCTAssertEqual(body["chat_id"] as? String, "-1001")
        XCTAssertEqual(body["message_thread_id"] as? Int, 42)
        XCTAssertEqual(body["parse_mode"] as? String, "MarkdownV2")
        let text = try XCTUnwrap(body["text"] as? String)
        XCTAssertTrue(text.contains("Workout finished"))
        XCTAssertFalse(text.contains("ZIP"))
        XCTAssertFalse(text.contains("schema_version"))
        XCTAssertFalse(request.url?.lastPathComponent == "sendDocument")
    }

    func test_sendClassifiesRateLimitAsKnownRejectionAndMalformedSuccessAsUnknown() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let limited = makeSender(
            session: makeSession(status: 429, json: #"{"ok":false,"parameters":{"retry_after":120}}"#),
            now: now
        )
        let limitedResult = await limited.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")
        XCTAssertEqual(limitedResult, .rejected(retryAfter: now.addingTimeInterval(120)))

        let malformed = makeSender(session: makeSession(status: 200, json: #"{"ok":true}"#), now: now)
        let malformedResult = await malformed.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")
        XCTAssertEqual(malformedResult, .deliveryUnknown)
    }

    func test_sendNeverRetriesBeforeTelegramRetryAfterEvenBeyondOneHour() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sender = makeSender(
            session: makeSession(status: 429, json: #"{"ok":false,"parameters":{"retry_after":7200}}"#),
            now: now
        )

        let result = await sender.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")

        XCTAssertEqual(result, .rejected(retryAfter: now.addingTimeInterval(7_200)))
    }

    func test_sendClassifiesServerFailuresAsAmbiguous() async {
        for status in [500, 502] {
            let sender = makeSender(session: makeSession(status: status, json: #"{"ok":false}"#))
            let result = await sender.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")
            XCTAssertEqual(result, .deliveryUnknown, "HTTP \(status)")
        }
    }

    func test_sendClassifiesHTTPRejectionTransportAmbiguityAndMissingAuthorization() async {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let rejected = makeSender(session: makeSession(status: 400, json: #"{"ok":false}"#), now: now)
        let rejectedResult = await rejected.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")
        XCTAssertEqual(rejectedResult, .rejected(retryAfter: now.addingTimeInterval(15 * 60)))

        let ambiguous = makeSender(
            session: makeSession(status: 0, json: "", failure: URLError(.networkConnectionLost)),
            now: now
        )
        let ambiguousResult = await ambiguous.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")
        XCTAssertEqual(ambiguousResult, .deliveryUnknown)

        let session = makeSession(status: 200, json: #"{"ok":true,"result":{"message_id":1}}"#)
        let unauthorized = AutomaticWorkoutTelegramSender(
            session: session,
            currentCredentials: { nil },
            clock: { now }
        )
        let unauthorizedResult = await unauthorized.send(candidate(), scopeID: "scope", timeZoneIdentifier: "UTC")
        XCTAssertEqual(unauthorizedResult, .rejected(retryAfter: nil))
        XCTAssertNil(StubProtocol.request)
    }

    private func makeSession(status: Int, json: String, failure: Error? = nil) -> URLSession {
        StubProtocol.status = status
        StubProtocol.data = Data(json.utf8)
        StubProtocol.request = nil
        StubProtocol.body = nil
        StubProtocol.failure = failure
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeSender(session: URLSession, now: Date = Date()) -> AutomaticWorkoutTelegramSender {
        AutomaticWorkoutTelegramSender(session: session, currentCredentials: {
            AutomaticWorkoutTelegramCredentials(
                scopeID: "scope",
                credentials: TelegramCredentials(
                    botToken: "fixture-token",
                    chatID: "-1001",
                    includeGitHubLink: false,
                    messageThreadID: 42
                )
            )
        }, clock: { now })
    }

    private func candidate() -> AutomaticWorkoutCandidate {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        return AutomaticWorkoutCandidate(
            id: UUID(),
            workout: WorkoutDTO(
                id: "private-id",
                type: .outdoorCycling,
                startDate: end.addingTimeInterval(-3_600),
                endDate: end,
                durationMinutes: 60,
                distanceKm: 25,
                activeEnergyKcal: 500,
                avgHeartRate: 140,
                maxHeartRate: 170,
                route: [],
                durationSeconds: 3_600,
                distanceMeters: 25_000
            )
        )
    }
}
