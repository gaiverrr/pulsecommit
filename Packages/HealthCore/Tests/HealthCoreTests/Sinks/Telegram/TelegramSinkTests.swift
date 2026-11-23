import XCTest
@testable import HealthCore

final class TelegramSinkTests: XCTestCase {
    private let credentials = TelegramCredentials(
        botToken: "111:AAA",
        chatID: "-1001234567890",
        verbosity: .standard,
        includeGitHubLink: false
    )

    override func setUp() {
        super.setUp()
        TelegramMockTransport.register()
    }

    override func tearDown() {
        TelegramMockTransport.unregister()
        super.tearDown()
    }

    func testHappyPathSendsMessagesAndDocument() async throws {
        let messageID = 42
        let documentMessageId = 43

        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json([
                "ok": true,
                "result": ["message_id": messageID, "chat": ["id": -1001234567890], "date": 0]
            ])
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json([
                "ok": true,
                "result": ["message_id": documentMessageId, "chat": ["id": -1001234567890], "date": 0]
            ])
        )

        let sink = TelegramSink(credentials: credentials, session: .shared)
        let snapshot = makeSnapshot()
        let files = [
            FileEntry(path: "2026-05-14/summary.json", data: Data("{\"a\":1}".utf8)),
            FileEntry(path: "2026-05-14/summary.md", data: Data("# hi".utf8))
        ]

        let result = try await sink.deliver(snapshot: snapshot, files: files)

        let expectedURL = URL(string: "https://t.me/c/1234567890/\(documentMessageId)")
        XCTAssertEqual(result, .success(reference: String(documentMessageId), url: expectedURL))

        let captured = TelegramMockTransport.captured
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].httpMethod, "POST")
        XCTAssertTrue(captured[0].url?.absoluteString.hasSuffix("/sendMessage") ?? false)
        XCTAssertEqual(captured[1].httpMethod, "POST")
        XCTAssertTrue(captured[1].url?.absoluteString.hasSuffix("/sendDocument") ?? false)

        let docBody = try XCTUnwrap(captured[1].httpBody)
        let bodyString = String(data: docBody, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(bodyString.contains("pulse-commit-2026-05-14.zip"))
        XCTAssertTrue(bodyString.contains("JSON archive"))
        XCTAssertTrue(bodyString.contains("2 files"))
        XCTAssertTrue(bodyString.contains("schema 1.0"))
    }

    func testLongMarkdownIsChunkedAcrossMultipleSendMessageCalls() async throws {
        TelegramMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/sendMessage",
            responses: [
                .json(["ok": true, "result": ["message_id": 10, "chat": ["id": 1], "date": 0]]),
                .json(["ok": true, "result": ["message_id": 11, "chat": ["id": 1], "date": 0]]),
                .json(["ok": true, "result": ["message_id": 12, "chat": ["id": 1], "date": 0]])
            ]
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 99, "chat": ["id": 1], "date": 0]])
        )

        let sink = TelegramSink(credentials: credentials, session: .shared, messageChunkLimit: 60)
        var snapshot = makeSnapshot()
        let start = snapshot.workouts[0].startDate
        let intervals = (0..<12).map { index in
            WorkoutRecordedIntervalDTO(
                kind: index.isMultiple(of: 2) ? .lap : .segment,
                startDate: start.addingTimeInterval(Double(index) * 60),
                endDate: start.addingTimeInterval(Double(index + 1) * 60),
                durationSeconds: 60
            )
        }
        snapshot.workouts = [WorkoutDTO(
            id: "long-run", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(3_900), durationMinutes: 60,
            distanceKm: 10, activeEnergyKcal: 612, avgHeartRate: 152,
            maxHeartRate: 176, route: [], durationSeconds: 3_599.5,
            distanceMeters: 10_000, recordedIntervals: intervals
        )]
        _ = try await sink.deliver(snapshot: snapshot, files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])

        let captured = TelegramMockTransport.captured
        let sendMessageCount = captured.filter { $0.url?.absoluteString.hasSuffix("/sendMessage") ?? false }.count
        let sendDocumentCount = captured.filter { $0.url?.absoluteString.hasSuffix("/sendDocument") ?? false }.count
        XCTAssertGreaterThan(sendMessageCount, 1)
        XCTAssertEqual(sendDocumentCount, 1)
        let texts = try captured
            .filter { $0.url?.absoluteString.hasSuffix("/sendMessage") ?? false }
            .map { request -> String in
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                return try XCTUnwrap(json["text"] as? String)
            }
        XCTAssertTrue(texts.allSatisfy { $0.count <= 60 })
        let joined = texts.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Duration: 59m 59.5s"), joined)
        XCTAssertTrue(joined.contains("2 more laps in JSON"), joined)
        XCTAssertTrue(joined.contains("2 more segments in JSON"), joined)
    }

    func testSendMessageBodyContainsMarkdownV2EscapedDayKey() async throws {
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json(["ok": true, "result": ["message_id": 1, "chat": ["id": 1], "date": 0]])
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 2, "chat": ["id": 1], "date": 0]])
        )
        let sink = TelegramSink(credentials: credentials, session: .shared)
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])
        let body = try XCTUnwrap(TelegramMockTransport.captured.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try XCTUnwrap(json["text"] as? String)
        // The bold title sits outside the fence, so its dayKey hyphens are escaped.
        XCTAssertTrue(text.contains("2026\\-05\\-14"), "expected escaped dayKey hyphens, got: \(text)")
        // The metric body is a fenced monospace block; inside it parens are
        // literal (MarkdownV2 escapes only ` and \ inside code), so the
        // workouts count renders unescaped.
        XCTAssertTrue(text.contains("```"), "expected a fenced code block, got: \(text)")
        XCTAssertTrue(text.contains("Workouts (1)"), "expected unescaped workouts count inside the fence, got: \(text)")
    }

    func testMessageURLIsNilForNonSupergroupChatId() async throws {
        let creds = TelegramCredentials(
            botToken: "111:AAA",
            chatID: "-987654",
            verbosity: .standard,
            includeGitHubLink: false
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json(["ok": true, "result": ["message_id": 1, "chat": ["id": -987654], "date": 0]])
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 2, "chat": ["id": -987654], "date": 0]])
        )
        let sink = TelegramSink(credentials: creds, session: .shared)
        let result = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])
        XCTAssertEqual(result, .success(reference: "2", url: nil))
    }

    func testCommitURLIncludedWhenEnabled() async throws {
        let creds = TelegramCredentials(
            botToken: "111:AAA",
            chatID: "-1001234567890",
            verbosity: .standard,
            includeGitHubLink: true
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json(["ok": true, "result": ["message_id": 1, "chat": ["id": 1], "date": 0]])
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 2, "chat": ["id": 1], "date": 0]])
        )
        let sink = TelegramSink(
            credentials: creds,
            commitURL: URL(string: "https://github.com/u/r/commit/abc1234")!,
            session: .shared
        )
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])
        let body = try XCTUnwrap(TelegramMockTransport.captured.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try XCTUnwrap(json["text"] as? String)
        XCTAssertTrue(text.contains("https://github.com/u/r/commit/abc1234"), "got: \(text)")
    }

    func testCommitURLOmittedWhenDisabled() async throws {
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json(["ok": true, "result": ["message_id": 1, "chat": ["id": 1], "date": 0]])
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 2, "chat": ["id": 1], "date": 0]])
        )
        let sink = TelegramSink(
            credentials: credentials,
            commitURL: URL(string: "https://github.com/u/r/commit/abc1234")!,
            session: .shared
        )
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])
        let body = try XCTUnwrap(TelegramMockTransport.captured.first?.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let text = try XCTUnwrap(json["text"] as? String)
        XCTAssertFalse(text.contains("View on GitHub"))
    }

    func testSendDocumentRetriesOn429() async throws {
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json(["ok": true, "result": ["message_id": 1, "chat": ["id": 1], "date": 0]])
        )
        TelegramMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/sendDocument",
            responses: [
                .json(
                    ["ok": false, "error_code": 429, "parameters": ["retry_after": 1]],
                    statusCode: 429
                ),
                .json(["ok": true, "result": ["message_id": 9, "chat": ["id": 1], "date": 0]])
            ]
        )
        let sleeps = SleepRecorder()
        let sink = TelegramSink(
            credentials: credentials,
            session: .shared,
            messageChunkLimit: 4096,
            sleep: { ns in sleeps.record(ns) }
        )
        let result = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])
        XCTAssertEqual(result, .success(reference: "9", url: URL(string: "https://t.me/c/1234567890/9")))
        let docCount = TelegramMockTransport.captured.filter { $0.url?.absoluteString.hasSuffix("/sendDocument") ?? false }.count
        XCTAssertEqual(docCount, 2)
        XCTAssertEqual(sleeps.values, [1_000_000_000])
    }

    func testRetryAfterValueIsHonored() async throws {
        TelegramMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/sendMessage",
            responses: [
                .json(
                    ["ok": false, "error_code": 429, "parameters": ["retry_after": 5]],
                    statusCode: 429
                ),
                .json(["ok": true, "result": ["message_id": 1, "chat": ["id": 1], "date": 0]])
            ]
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 2, "chat": ["id": 1], "date": 0]])
        )
        let sleeps = SleepRecorder()
        let sink = TelegramSink(
            credentials: credentials,
            session: .shared,
            messageChunkLimit: 4096,
            sleep: { ns in sleeps.record(ns) }
        )
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])
        XCTAssertEqual(sleeps.values, [5_000_000_000])
    }

func testApiOkFalseSurfacesAsApiError() async throws {
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json([
                "ok": false,
                "error_code": 400,
                "description": "Bad Request: chat not found"
            ])
        )
        let sink = TelegramSink(credentials: credentials, session: .shared)
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: [
                FileEntry(path: "x.json", data: Data("{}".utf8))
            ])
            XCTFail("expected apiError")
        } catch let TelegramSinkError.apiError(description, errorCode, _) {
            XCTAssertEqual(description, "Bad Request: chat not found")
            XCTAssertEqual(errorCode, 400)
        }
    }

    func testCredentialsRedactsTokenInDescription() {
        let creds = TelegramCredentials(botToken: "SECRET-TOKEN-12345", chatID: "-100123")
        XCTAssertFalse(String(describing: creds).contains("SECRET-TOKEN-12345"))
        XCTAssertFalse(String(reflecting: creds).contains("SECRET-TOKEN-12345"))
    }

    func testSendMessageRetriesOn429WithRetryAfter() async throws {
        TelegramMockTransport.addRouteSequence(
            method: "POST",
            pathSuffix: "/sendMessage",
            responses: [
                .json(
                    [
                        "ok": false,
                        "error_code": 429,
                        "description": "Too Many Requests",
                        "parameters": ["retry_after": 1]
                    ],
                    statusCode: 429
                ),
                .json(["ok": true, "result": ["message_id": 77, "chat": ["id": 1], "date": 0]])
            ]
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 78, "chat": ["id": 1], "date": 0]])
        )

        let sleeps = SleepRecorder()
        let sink = TelegramSink(
            credentials: credentials,
            session: .shared,
            messageChunkLimit: 4096,
            sleep: { ns in sleeps.record(ns) }
        )
        let snapshot = makeSnapshot()
        let files = [FileEntry(path: "x.json", data: Data("{}".utf8))]

        let result = try await sink.deliver(snapshot: snapshot, files: files)

        XCTAssertEqual(result, .success(reference: "78", url: URL(string: "https://t.me/c/1234567890/78")))

        let captured = TelegramMockTransport.captured
        let sendMessageCount = captured.filter { $0.url?.absoluteString.hasSuffix("/sendMessage") ?? false }.count
        XCTAssertEqual(sendMessageCount, 2)
        XCTAssertEqual(sleeps.values, [1_000_000_000])
    }

    func testForumThreadIdIsForwardedToBothSendMessageAndSendDocument() async throws {
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendMessage",
            response: .json(["ok": true, "result": ["message_id": 1, "chat": ["id": 1], "date": 0]])
        )
        TelegramMockTransport.addRoute(
            method: "POST",
            pathSuffix: "/sendDocument",
            response: .json(["ok": true, "result": ["message_id": 2, "chat": ["id": 1], "date": 0]])
        )
        let forumCredentials = TelegramCredentials(
            botToken: "111:AAA",
            chatID: "-1001234567890",
            verbosity: .standard,
            includeGitHubLink: false,
            messageThreadID: 42
        )
        let sink = TelegramSink(credentials: forumCredentials, session: .shared)
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: [
            FileEntry(path: "x.json", data: Data("{}".utf8))
        ])

        let captured = TelegramMockTransport.captured
        let messageRequest = captured.first { $0.url?.absoluteString.hasSuffix("/sendMessage") ?? false }
        let documentRequest = captured.first { $0.url?.absoluteString.hasSuffix("/sendDocument") ?? false }

        let messageBody = try XCTUnwrap(messageRequest?.httpBody)
        let messageJson = try XCTUnwrap(JSONSerialization.jsonObject(with: messageBody) as? [String: Any])
        XCTAssertEqual(messageJson["message_thread_id"] as? Int, 42)

        let docBody = try XCTUnwrap(documentRequest?.httpBody)
        let docBodyString = String(data: docBody, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(docBodyString.contains("name=\"message_thread_id\""))
        XCTAssertTrue(docBodyString.contains("\r\n\r\n42\r\n"))
    }

    private final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [UInt64] = []
        var values: [UInt64] {
            lock.lock(); defer { lock.unlock() }
            return _values
        }
        func record(_ ns: UInt64) {
            lock.lock(); defer { lock.unlock() }
            _values.append(ns)
        }
    }

    private func makeSnapshot() -> DailySnapshot {
        var snap = DailySnapshot(
            date: SampleFixtures.iso("2026-05-14T00:00:00Z"),
            timezone: "UTC",
            generatedAt: SampleFixtures.iso("2026-05-14T22:30:12Z"),
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = [
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count"),
            "sleep": SummaryFragment(metrics: ["duration_minutes": .int(437)])
        ]
        snap.workouts = [
            WorkoutDTO(
                id: "7f3a",
                type: .outdoorRun,
                startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
                endDate: SampleFixtures.iso("2026-05-14T07:38:00Z"),
                durationMinutes: 38,
                distanceKm: 6.2,
                activeEnergyKcal: 410,
                avgHeartRate: 152,
                maxHeartRate: 174,
                route: []
            )
        ]
        return snap
    }
}
