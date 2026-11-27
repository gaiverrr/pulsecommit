import XCTest
@testable import HealthCore

final class WebhookSinkTests: XCTestCase {
    private let endpoint = URL(string: "https://hooks.example.com/hooks/pulse?route=daily")!
    private let summaryJSON = Data("{\"schema_version\":\"1.0\",\"date\":\"2026-05-14\",\"value\":1.50,\"nested\":{\"a\":[1,2]}}".utf8)

    private final class SleepLog: @unchecked Sendable {
        private let lock = NSLock()
        private var _values: [UInt64] = []
        func append(_ value: UInt64) { lock.lock(); _values.append(value); lock.unlock() }
        var values: [UInt64] { lock.lock(); defer { lock.unlock() }; return _values }
    }

    private func makeSink(
        token: String? = "s3cret-token",
        tokenHeader: String = "Authorization",
        sleeps: SleepLog = SleepLog(),
        authorize: @escaping @Sendable () async -> Bool = { true }
    ) throws -> WebhookSink {
        let configuration = try WebhookConfiguration(endpoint: endpoint, token: token, tokenHeader: tokenHeader)
        return WebhookSink(
            configuration: configuration,
            session: WebhookMockTransport.makeSession(),
            minimumInterval: 0,
            sleep: { sleeps.append($0) },
            authorizePayload: authorize
        )
    }

    private func makeSnapshot() -> DailySnapshot {
        DailySnapshot(
            date: SampleFixtures.iso("2026-05-14T00:00:00Z"),
            timezone: "UTC",
            generatedAt: SampleFixtures.iso("2026-05-14T22:30:12Z"),
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.2"
        )
    }

    private func makeFiles(summary: Data? = nil) -> [FileEntry] {
        [
            FileEntry(path: "2026-05-14/summary.json", data: summary ?? summaryJSON),
            FileEntry(path: "2026-05-14/summary.md", data: Data("# Pulse Commit\nsteps 12 483".utf8)),
            FileEntry(path: "2026-05-14/samples/steps.json", data: Data(repeating: 0x20, count: 1234))
        ]
    }

    private func ok(_ status: Int = 200, headers: [String: String] = [:]) -> WebhookMockTransport.Outcome {
        .response(.init(statusCode: status, headers: headers))
    }

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func test_envelopeCarriesSummaryUnchangedMarkdownAndManifest() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink()

        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())

        let request = try XCTUnwrap(WebhookMockTransport.captured.first)
        let json = try body(request)
        XCTAssertEqual(json["schema_version"] as? String, "1.0")
        XCTAssertEqual(json["event_type"] as? String, "daily_export")
        XCTAssertEqual(json["date"] as? String, "2026-05-14")
        XCTAssertEqual(json["summary_markdown"] as? String, "# Pulse Commit\nsteps 12 483")

        let embedded = try XCTUnwrap(json["summary"] as? NSDictionary)
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: summaryJSON) as? NSDictionary)
        XCTAssertEqual(embedded, original)
        let raw = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(raw.contains(String(decoding: summaryJSON, as: UTF8.self)))

        let manifest = try XCTUnwrap(json["files"] as? [[String: Any]])
        XCTAssertEqual(manifest.map { $0["path"] as? String }, ["summary.json", "summary.md", "samples/steps.json"])
        XCTAssertEqual(manifest.last?["bytes"] as? Int, 1234)
    }

    func test_requestHeadersIncludeTokenIdempotencyAndUserAgent() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink()

        let result = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())

        let request = try XCTUnwrap(WebhookMockTransport.captured.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "PulseCommit/1.0.2")
        let key = try XCTUnwrap(request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), key)
        XCTAssertTrue(key.hasPrefix("pc-2026-05-14-"))
        XCTAssertEqual(key.count, "pc-2026-05-14-".count + 12)
        XCTAssertEqual(try body(request)["idempotency_key"] as? String, key)
        XCTAssertEqual(result, .success(reference: key, url: nil))
    }

    func test_customTokenHeaderSendsRawToken() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink(tokenHeader: "X-Gitlab-Token")

        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())

        let request = try XCTUnwrap(WebhookMockTransport.captured.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Gitlab-Token"), "s3cret-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func test_emptyTokenSendsNoAuthHeader() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink(token: "")

        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())

        XCTAssertNil(WebhookMockTransport.captured.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func test_idempotencyKeyIsStableAcrossRetriesAndChangesWithSummary() async throws {
        WebhookMockTransport.reset([ok(503), ok()])
        let sink = try makeSink()
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
        let keys = WebhookMockTransport.captured.map { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        XCTAssertEqual(keys.count, 2)
        XCTAssertEqual(keys[0], keys[1])

        WebhookMockTransport.reset([ok()])
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles(summary: Data("{\"other\":true}".utf8)))
        XCTAssertNotEqual(WebhookMockTransport.captured.first?.value(forHTTPHeaderField: "Idempotency-Key"), keys[0])
    }

    func test_deliverDailyReportsStatusAndKey() async throws {
        WebhookMockTransport.reset([ok(202)])
        let sink = try makeSink()

        let delivery = try await sink.deliverDaily(snapshot: makeSnapshot(), files: makeFiles(), onAttempt: nil)

        let request = try XCTUnwrap(WebhookMockTransport.captured.first)
        XCTAssertEqual(delivery.statusCode, 202)
        XCTAssertEqual(delivery.idempotencyKey, request.value(forHTTPHeaderField: "Idempotency-Key"))
        XCTAssertEqual(sink.host, "hooks.example.com")
    }

    func test_any2xxSucceeds() async throws {
        for status in [200, 202, 204] {
            WebhookMockTransport.reset([ok(status)])
            let sink = try makeSink()
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
            XCTAssertEqual(WebhookMockTransport.captured.count, 1, "status \(status)")
        }
    }

    func test_clientErrorsFailWithoutRetry() async throws {
        for status in [400, 401, 404, 413] {
            WebhookMockTransport.reset([ok(status), ok()])
            let sink = try makeSink()
            do {
                _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
                XCTFail("expected failure for \(status)")
            } catch let error as WebhookSinkError {
                XCTAssertEqual(error, .httpStatus(status))
            }
            XCTAssertEqual(WebhookMockTransport.captured.count, 1, "status \(status)")
        }
    }

    func test_retryAfterIsHonouredOn429() async throws {
        WebhookMockTransport.reset([ok(429, headers: ["Retry-After": "7"]), ok()])
        let sleeps = SleepLog()
        let sink = try makeSink(sleeps: sleeps)
        let attempts = SleepLog()

        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles(), onAttempt: { attempt, total, _ in
            attempts.append(UInt64(attempt))
            XCTAssertEqual(total, 3)
        })

        XCTAssertEqual(WebhookMockTransport.captured.count, 2)
        XCTAssertEqual(sleeps.values, [7_000_000_000])
        XCTAssertEqual(attempts.values, [1])
    }

    func test_serverErrorsAndTransportFailuresRetryThenGiveUp() async throws {
        WebhookMockTransport.reset([.failure(.timedOut), ok(502), ok(503)])
        let sink = try makeSink()
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
            XCTFail("expected failure")
        } catch let error as WebhookSinkError {
            XCTAssertEqual(error, .httpStatus(503))
        }
        XCTAssertEqual(WebhookMockTransport.captured.count, 3)
    }

    func test_408And5xxRecover() async throws {
        WebhookMockTransport.reset([ok(408), ok(500), ok(201)])
        let sink = try makeSink()
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
        XCTAssertEqual(WebhookMockTransport.captured.count, 3)
    }

    func test_redirectIsRefusedAndNotFollowed() async throws {
        WebhookMockTransport.reset([ok(302, headers: ["Location": "https://elsewhere.example.net/steal"]), ok()])
        let sink = try makeSink()
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
            XCTFail("expected failure")
        } catch let error as WebhookSinkError {
            XCTAssertEqual(error, .redirectRefused(302))
        }
        XCTAssertEqual(WebhookMockTransport.captured.map { $0.url?.host }, ["hooks.example.com"])
    }

    func test_consentDeniedSendsNothing() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink(authorize: { false })
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
            XCTFail("expected consent failure")
        } catch HealthExportAuthorizationError.consentRequired {
        }
        XCTAssertTrue(WebhookMockTransport.captured.isEmpty)
    }

    func test_missingSummaryFails() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink()
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: [FileEntry(path: "2026-05-14/summary.md", data: Data())])
            XCTFail("expected failure")
        } catch let error as WebhookSinkError {
            XCTAssertEqual(error, .missingSummary)
        }
        XCTAssertTrue(WebhookMockTransport.captured.isEmpty)
    }

    func test_sendTestPostsSyntheticBodyWithoutConsent() async throws {
        WebhookMockTransport.reset([ok(204)])
        let sink = try makeSink(authorize: { false })

        let status = try await sink.sendTest(appVersion: "1.0.2")

        XCTAssertEqual(status, 204)
        let request = try XCTUnwrap(WebhookMockTransport.captured.first)
        let json = try body(request)
        XCTAssertEqual(json["event_type"] as? String, "test")
        XCTAssertNil(json["summary"])
        XCTAssertNil(json["summary_markdown"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer s3cret-token")
    }

    func test_firstAttemptReportsNoRetryAndRetriesCarryReasons() async throws {
        WebhookMockTransport.reset([ok(503), .failure(.networkConnectionLost), ok()])
        final class Reasons: @unchecked Sendable {
            let lock = NSLock(); var items: [String] = []
            func add(_ s: String) { lock.lock(); items.append(s); lock.unlock() }
        }
        let reasons = Reasons()
        let sleeps = SleepLog()
        let sink = try makeSink(sleeps: sleeps)
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles(), onAttempt: { attempt, total, reason in
            reasons.add("\(attempt)/\(total) \(reason)")
        })
        XCTAssertEqual(reasons.items, ["1/3 HTTP 503", "2/3 network error"])
        XCTAssertEqual(sleeps.values, [1_000_000_000, 2_000_000_000])
    }

    func test_retryAfterOn503AndCapAt60Seconds() async throws {
        WebhookMockTransport.reset([ok(503, headers: ["Retry-After": "3"]), ok(429, headers: ["Retry-After": "600"]), ok()])
        let sleeps = SleepLog()
        let sink = try makeSink(sleeps: sleeps)
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
        XCTAssertEqual(sleeps.values, [3_000_000_000, 60_000_000_000])
    }

    func test_consentRevokedBetweenRetriesStopsDelivery() async throws {
        WebhookMockTransport.reset([ok(503), ok()])
        final class Gate: @unchecked Sendable { let lock = NSLock(); var calls = 0 }
        let gate = Gate()
        let sink = try makeSink(authorize: {
            gate.lock.lock(); defer { gate.lock.unlock() }
            gate.calls += 1
            return gate.calls == 1
        })
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
            XCTFail("expected consent failure")
        } catch HealthExportAuthorizationError.consentRequired {
        }
        XCTAssertEqual(WebhookMockTransport.captured.count, 1)
    }

    func test_requestUsesThirtySecondTimeout() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink()
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
        XCTAssertEqual(WebhookMockTransport.captured.first?.timeoutInterval, 30)
    }

    func test_cancellationIsNotReportedAsNetworkError() async throws {
        WebhookMockTransport.reset([.failure(.cancelled), ok()])
        let sink = try makeSink()
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles())
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }
        XCTAssertEqual(WebhookMockTransport.captured.count, 1)
    }

    func test_invalidSummaryIsRejectedAndBOMIsStripped() async throws {
        WebhookMockTransport.reset([ok()])
        let sink = try makeSink()
        do {
            _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles(summary: Data("not json".utf8)))
            XCTFail("expected failure")
        } catch let error as WebhookSinkError {
            XCTAssertEqual(error, .invalidSummary)
        }
        XCTAssertTrue(WebhookMockTransport.captured.isEmpty)

        WebhookMockTransport.reset([ok()])
        _ = try await sink.deliver(snapshot: makeSnapshot(), files: makeFiles(summary: Data([0xEF, 0xBB, 0xBF]) + summaryJSON))
        XCTAssertNotNil(try body(XCTUnwrap(WebhookMockTransport.captured.first))["summary"] as? [String: Any])
    }

    func test_pacerSpacesConsecutiveRequests() async throws {
        let pacer = RequestPacer()
        let sleeps = SleepLog()
        try await pacer.wait(minimumInterval: 2, sleep: { sleeps.append($0) })
        try await pacer.wait(minimumInterval: 2, sleep: { sleeps.append($0) })
        try await pacer.wait(minimumInterval: 2, sleep: { sleeps.append($0) })
        XCTAssertEqual(sleeps.values.count, 2)
        XCTAssertGreaterThan(sleeps.values[0], 1_900_000_000)
        XCTAssertLessThanOrEqual(sleeps.values[0], 2_000_000_000)
        XCTAssertGreaterThan(sleeps.values[1], 3_900_000_000)
    }

    func test_redirectBlockerDeclinesRedirect() async {
        let blocker = RedirectBlocker()
        let response = HTTPURLResponse(url: endpoint, statusCode: 307, httpVersion: nil, headerFields: nil)!
        let task = URLSession.shared.dataTask(with: endpoint)
        let next = await blocker.urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: URLRequest(url: URL(string: "https://elsewhere.example.net")!))
        XCTAssertNil(next)
    }

    func test_transportFailuresUsePlainWording() {
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1009).localizedDescription, "No internet connection (-1009)")
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1001).localizedDescription, "The endpoint did not respond in 30 seconds (-1001)")
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1202).localizedDescription, "The endpoint's HTTPS certificate is not trusted (-1202)")
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1200).localizedDescription, "The HTTPS connection to the endpoint failed (-1200)")
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1205).localizedDescription, "The endpoint rejected the client certificate (-1205)")
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1206).localizedDescription, "The endpoint requires a client certificate (-1206)")
        XCTAssertEqual(WebhookSinkError.transportFailure(code: -1004).localizedDescription, "Network error (-1004)")
    }

    func test_errorDescriptionsNeverContainSecrets() {
        let errors: [WebhookSinkError] = [.httpStatus(401), .redirectRefused(301), .transportFailure(code: -1001), .invalidResponse, .missingSummary, .invalidSummary]
        for error in errors {
            let text = error.localizedDescription
            XCTAssertFalse(text.contains("s3cret"))
            XCTAssertFalse(text.contains("/hooks/pulse"))
            XCTAssertFalse(text.isEmpty)
        }
    }
}

final class WebhookConfigurationTests: XCTestCase {
    func test_acceptsHTTPSWithPathAndQuery() throws {
        let config = try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com:8443/a/b?x=1")!, token: "t", tokenHeader: "Authorization")
        XCTAssertEqual(config.host, "hooks.example.com")
    }

    func test_rejectsInsecureOrMalformedEndpoints() {
        let bad = [
            "http://hooks.example.com/x",
            "ftp://hooks.example.com/x",
            "https://user:pass@hooks.example.com/x",
            "https:/nohost"
        ]
        for string in bad {
            XCTAssertThrowsError(try WebhookConfiguration(endpoint: URL(string: string)!, token: nil, tokenHeader: "Authorization"), string)
        }
    }

    func test_rejectsBadOrReservedHeaderNames() {
        for name in ["", "Bad Header", "X:Y", "Content-Type", "content-length", "Host", "Idempotency-Key", "X-Request-ID", "User-Agent", "Proxy-Authorization", "Transfer-Encoding", "Cookie"] {
            XCTAssertThrowsError(try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com")!, token: "t", tokenHeader: name), name)
        }
    }

    func test_rejectsLocalNetworkHosts() {
        for host in ["localhost", "printer.local", "10.0.0.5", "192.168.1.20", "172.20.0.1", "127.0.0.1", "169.254.1.1", "[::1]", "[fd12::1]",
                     "[::ffff:192.168.1.5]", "[::ffff:127.0.0.1]", "[::ffff:c0a8:105]", "[fe90::1]", "[febf::1]", "[fe80::1]", "[fc00::1]", "[::]", "0.0.0.0", "0.1.2.3",
                     "127.1", "2130706433", "0x7f000001", "010.0.0.1", "1.2.3", "foo.localhost", "[0:0:0:0:0:0:0:1]"] {
            XCTAssertThrowsError(try WebhookConfiguration(endpoint: URL(string: "https://\(host)/hook")!, token: nil), host)
        }
        for host in ["agent.tail1a2b.ts.net", "172.32.0.1", "hooks.example.com", "100.100.1.1", "100.64.0.1", "172.15.0.1", "8.8.8.8", "[2001:db8::1]", "[::ffff:8.8.8.8]", "[fec0::1]", "1.2.3.4.example.com"] {
            XCTAssertNoThrow(try WebhookConfiguration(endpoint: URL(string: "https://\(host)/hook")!, token: nil), host)
        }
    }

    func test_trailingNewlineInPastedTokenIsTrimmed() throws {
        let config = try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com")!, token: "abc123\n", tokenHeader: "Authorization\n")
        XCTAssertEqual(config.token, "abc123")
        XCTAssertEqual(config.tokenHeader, "Authorization")
    }

    func test_rejectsTokensWithLineBreaks() {
        XCTAssertThrowsError(try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com")!, token: "a\r\nX-Evil: 1", tokenHeader: "Authorization"))
    }

    func test_identityExcludesToken() throws {
        let a = try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com/p")!, token: "one", tokenHeader: "Authorization")
        let b = try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com/p")!, token: "two", tokenHeader: "Authorization")
        let c = try WebhookConfiguration(endpoint: URL(string: "https://hooks.example.com/q")!, token: "one", tokenHeader: "Authorization")
        XCTAssertEqual(a.consentIdentity, b.consentIdentity)
        XCTAssertNotEqual(a.consentIdentity, c.consentIdentity)
    }

    func test_identityTracksTheExactURL() throws {
        func identity(_ string: String) throws -> WebhookConsentIdentity {
            try WebhookConfiguration(endpoint: URL(string: string)!, token: nil).consentIdentity
        }
        let base = try identity("https://hooks.example.com/hook?chat_id=1")
        XCTAssertNotEqual(base, try identity("https://hooks.example.com/hook?chat_id=2"))
        XCTAssertNotEqual(base, try identity("https://hooks.example.com/hook"))
        XCTAssertNotEqual(try identity("https://hooks.example.com/hook"), try identity("https://hooks.example.com/hook/"))
        XCTAssertNotEqual(try identity("https://hooks.example.com/a%2Fb"), try identity("https://hooks.example.com/a/b"))
        XCTAssertNotEqual(try identity("https://hooks.example.com:8443/hook"), try identity("https://hooks.example.com/hook"))
        XCTAssertEqual(try identity("https://HOOKS.example.com/hook?chat_id=1"), base)
        XCTAssertEqual(try identity("https://hooks.example.com/hook?chat_id=1#frag"), base)
    }

    func test_generatedTokensAreLongAndUnique() {
        let a = WebhookConfiguration.generateToken()
        let b = WebhookConfiguration.generateToken()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 43)
        XCTAssertTrue(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }
}
