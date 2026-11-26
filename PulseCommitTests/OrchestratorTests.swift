import XCTest
import HealthCore
@testable import PulseCommit

// MARK: - OrchestratorTestHarness

struct OrchestratorTestHarness {
    let orchestrator: Orchestrator
    let request: ExportRequest

    static func makeWith(
        enabledCategoryIds: Set<String>,
        windowDays: Int
    ) async throws -> OrchestratorTestHarness {
        let fixedClock = Date(timeIntervalSince1970: 1_700_000_000)
        let cats: [any HealthCategory] = enabledCategoryIds.sorted().map { id in
            StubOrchestratorCategory(id: id)
        }
        let registry = CategoryRegistry(categories: cats)
        let pipeline = SnapshotPipeline(
            registry: registry,
            timezone: TimeZone(identifier: "UTC")!,
            deviceName: "iPhone-Test",
            appVersion: "1.0.0",
            clock: { fixedClock }
        )

        let noopSink = NoOpSink(id: "github")

        let historyStore = try await MainActor.run { try HistoryStore.inMemory() }
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: TimeZone(identifier: "UTC")!),
            pipeline: pipeline,
            sinks: [noopSink],
            historyStore: historyStore,
            clock: { fixedClock }
        )

        let request = ExportRequest(
            mode: windowDays == 1 ? .todayLive : .lastNDays(windowDays),
            enabledCategoryIds: enabledCategoryIds,
            enabledSinkIds: ["github"]
        )

        return OrchestratorTestHarness(orchestrator: orchestrator, request: request)
    }
}

private struct StubOrchestratorCategory: HealthCategory {
    let id: String
    var displayName: String { id }
    // One in-window sample so harness runs carry data: a fully empty window
    // is now a failed run (healthDataUnreadable), tested separately.
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        [QuantitySampleDTO(
            categoryID: id,
            startDate: from.addingTimeInterval(60),
            endDate: from.addingTimeInterval(120),
            value: 1,
            unit: "count",
            sourceName: "iPhone-Test",
            sourceBundleID: "com.apple.health"
        )]
    }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SummaryFragment(metrics: ["count": .int(samples.count)], unit: "count")
    }
}

private struct NoOpSink: Sink {
    let id: String
    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        .success(reference: "test", url: nil)
    }
}

// Task 3's `ActorIsolatedEvents` is `private` in SnapshotPipelineTests.swift.
// Declare a separate `private` copy here for this test file.
private actor ActorIsolatedEvents {
    private(set) var events: [RunProgress] = []
    func append(_ event: RunProgress) { events.append(event) }
}

// MARK: - StubCategory (existing)

private struct StubCategory: HealthCategory {
    let id: String
    let displayName: String = "Stub"
    let samples: [any SampleDTO]

    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        samples.filter { $0.startDate >= from && $0.startDate <= to }
    }

    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        var fragment = SummaryFragment()
        fragment.metrics["count"] = .int(samples.count)
        return fragment
    }
}

private struct ThrowingCategory: HealthCategory {
    let id: String
    let displayName: String = "Throwing"
    struct ReadError: Error {}
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { throw ReadError() }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment { SummaryFragment() }
}

/// Returns a scripted sequence of `isProtectedDataAvailable` answers so a test
/// can simulate the device locking partway through a run (e.g. [true, false]).
private actor ProtectedDataGate {
    private var results: [Bool]
    init(_ results: [Bool]) { self.results = results }
    func next() -> Bool { results.isEmpty ? true : results.removeFirst() }
}

private actor RecordingSink: Sink {
    nonisolated let id: String
    private(set) var deliveredCount: Int = 0
    private(set) var deliveredDates: [Date] = []
    private let reference: String
    private let url: URL?

    init(id: String, reference: String = "ref", url: URL? = nil) {
        self.id = id
        self.reference = reference
        self.url = url
    }

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        deliveredCount += 1
        deliveredDates.append(snapshot.date)
        return .success(reference: reference, url: url)
    }

    func callCount() -> Int { deliveredCount }
    func dates() -> [Date] { deliveredDates }
}

private struct ThrowingSink: Sink {
    let id: String
    struct Boom: Error {}
    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        throw Boom()
    }
}

private struct SessionExpiredSink: Sink {
    let id: String
    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        throw GitHubAuthError.sessionExpired
    }
}

private actor ScriptedConsentVerifier {
    private var values: [Bool]
    init(_ values: [Bool]) { self.values = values }
    func next() -> Bool { values.isEmpty ? false : values.removeFirst() }
}

private actor ScriptedHistoryValidator {
    private var results: [Result<Void, HealthHistoryCoverageError>]
    private(set) var count = 0

    init(_ results: [Result<Void, HealthHistoryCoverageError>]) {
        self.results = results
    }

    func validate(from: Date, to: Date, enabledCategoryIds: Set<String>) throws {
        count += 1
        try results.removeFirst().get()
    }
}

private actor InvocationCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

private actor PausedFirstDeliverySink: Sink {
    nonisolated let id = "github"
    private var started: CheckedContinuation<Void, Never>?
    private var resumeFirst: CheckedContinuation<Void, Never>?
    private var count = 0

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        count += 1
        if count == 1 {
            started?.resume()
            started = nil
            await withCheckedContinuation { resumeFirst = $0 }
        }
        return .success(reference: "fixture", url: nil)
    }

    func waitForFirstDelivery() async {
        if count == 0 { await withCheckedContinuation { started = $0 } }
    }

    func releaseFirstDelivery() { resumeFirst?.resume(); resumeFirst = nil }
    func callCount() -> Int { count }
}

private final class ConsentBoundaryURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var capturedStorage: [URLRequest] = []
    private static var onRequestStorage: ((URLRequest) -> Void)?
    private static var refreshJSONStorage: String?

    static var captured: [URLRequest] { lock.withLock { capturedStorage } }
    static func reset(onRequest: ((URLRequest) -> Void)? = nil, refreshJSON: String? = nil) {
        lock.withLock {
            capturedStorage.removeAll()
            onRequestStorage = onRequest
            refreshJSONStorage = refreshJSON
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let onRequest = Self.lock.withLock { () -> ((URLRequest) -> Void)? in
            Self.capturedStorage.append(request)
            return Self.onRequestStorage
        }
        onRequest?(request)
        let path = request.url?.path ?? ""
        let method = request.httpMethod ?? ""
        let (status, json): (Int, String)
        switch (method, path) {
        case ("POST", "/login/oauth/access_token"):
            (status, json) = (200, Self.lock.withLock { Self.refreshJSONStorage } ?? #"{"error":"fixture_not_configured"}"#)
        case ("POST", "/login/device/code"):
            (status, json) = (200, #"{"device_code":"device","user_code":"ABCD-1234","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)
        case ("GET", "/user/installations"):
            (status, json) = (200, #"{"installations":[{"id":3,"account":{"login":"octocat"}}]}"#)
        case ("GET", let path) where path.hasSuffix("/getMe"):
            (status, json) = (200, #"{"ok":true,"result":{"id":1,"is_bot":true,"first_name":"Fixture"}}"#)
        case ("GET", let path) where path.hasSuffix("/git/ref/heads/main"):
            (status, json) = (200, #"{"ref":"refs/heads/main","object":{"sha":"parent","type":"commit","url":"u"}}"#)
        case ("GET", let path) where path.hasSuffix("/git/commits/parent"):
            (status, json) = (200, #"{"sha":"parent","tree":{"sha":"base-tree","url":"u"}}"#)
        case ("POST", let path) where path.hasSuffix("/git/blobs"):
            (status, json) = (201, #"{"sha":"blob","url":"u"}"#)
        case ("POST", let path) where path.hasSuffix("/git/trees"):
            (status, json) = (201, #"{"sha":"tree","url":"u"}"#)
        case ("POST", let path) where path.hasSuffix("/git/commits"):
            (status, json) = (201, #"{"sha":"commit","url":"u","html_url":"https://github.com/octocat/health/commit/commit"}"#)
        case ("PATCH", let path) where path.hasSuffix("/git/refs/heads/main"):
            (status, json) = (200, #"{"ref":"refs/heads/main","object":{"sha":"commit","type":"commit","url":"u"}}"#)
        case ("POST", let path) where path.hasSuffix("/sendMessage") || path.hasSuffix("/sendDocument"):
            (status, json) = (200, #"{"ok":true,"result":{"message_id":42}}"#)
        default:
            (status, json) = (500, #"{"message":"Unexpected fixture request"}"#)
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}

@MainActor
final class OrchestratorTests: XCTestCase {
    private let timezone = TimeZone(identifier: "UTC")!

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    private func makePipeline(clockDate: Date) -> SnapshotPipeline {
        let sampleStart = clockDate.addingTimeInterval(-18 * 60 * 60)
        let steps = StubCategory(
            id: "steps",
            samples: [
                QuantitySampleDTO(
                    categoryID: "steps",
                    startDate: sampleStart,
                    endDate: sampleStart.addingTimeInterval(60),
                    value: 100,
                    unit: "count",
                    sourceName: "iPhone",
                    sourceBundleID: "com.apple.health"
                )
            ]
        )
        return SnapshotPipeline(
            registry: CategoryRegistry(categories: [steps]),
            timezone: timezone,
            deviceName: "iPhone Test",
            appVersion: "1.0.0",
            clock: { clockDate }
        )
    }

    private func uniqueDefaults() -> UserDefaults {
        let suite = "OrchestratorTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func requirement(_ sinkID: String) -> ConsentRequirement {
        ConsentRequirement(
            sinkID: sinkID,
            destination: sinkID == "telegram"
                ? .telegram(chatID: "-100123", messageThreadID: 42)
                : .github(owner: "octocat", repo: "health", branch: "main", subdir: "exports")
        )
    }

    func test_githubRefreshRejectionStoresSafeHistoryWithoutWritesOrTokenLoss() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let stored = StoredTokens(
            accessToken: "gho_expired_fixture",
            refreshToken: "ghr_private_fixture",
            accessExpiresAt: now.addingTimeInterval(-60),
            refreshExpiresAt: now.addingTimeInterval(86_400)
        )
        let vault = InMemoryTokenVault(initial: stored)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsentBoundaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let provider = DeviceFlowCredentialProvider(
            vault: vault,
            client: GitHubDeviceFlowClient(session: session, clientID: "Iv1.fixture"),
            clock: { now },
            owner: "octocat", repo: "health", branch: "main"
        )
        let history = try HistoryStore.inMemory()
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [GitHubSink(credentialProvider: provider, session: session)],
            historyStore: history,
            clock: { now }
        )
        ConsentBoundaryURLProtocol.reset(refreshJSON: #"{"error":"incorrect_client_credentials","error_description":"ghr_private_fixture https://example.com"}"#)

        let status = await orchestrator.run(.init(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        ))

        XCTAssertEqual(status, .failed)
        XCTAssertEqual(ConsentBoundaryURLProtocol.captured.count, 1)
        XCTAssertEqual(ConsentBoundaryURLProtocol.captured.first?.url?.path, "/login/oauth/access_token")
        XCTAssertEqual(ConsentBoundaryURLProtocol.captured.first?.httpMethod, "POST")
        XCTAssertNil(try history.cursor())
        let retainedTokens = try await vault.load()
        XCTAssertEqual(retainedTokens, stored)
        let entry = try XCTUnwrap(history.recentEntries(limit: 1).first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertNil(entry.errorKind)
        XCTAssertEqual(entry.errorMessage, "sink failed: Unexpected response from GitHub (HTTP 200; incorrect_client_credentials).")
        XCTAssertFalse(entry.errorMessage?.contains("ghr_private_fixture") ?? true)
        XCTAssertFalse(entry.errorMessage?.contains("example.com") ?? true)

        ConsentBoundaryURLProtocol.reset(refreshJSON: #"{"error":"ghr_private_fixture https://example.com"}"#)
        let unknownCodeStatus = await orchestrator.run(.init(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        ))
        XCTAssertEqual(unknownCodeStatus, .failed)
        XCTAssertEqual(ConsentBoundaryURLProtocol.captured.count, 1)
        XCTAssertNil(try history.cursor())
        let tokensAfterUnknownCode = try await vault.load()
        XCTAssertEqual(tokensAfterUnknownCode, stored)
        let entries = try history.recentEntries(limit: 2)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries.contains {
            $0.errorMessage == "sink failed: Unexpected response from GitHub (HTTP 200)."
        })
        XCTAssertFalse(entries.contains { $0.errorMessage?.contains("ghr_private_fixture") == true })
    }

    func test_missingConsentFailsBeforeHealthDeliveryOrCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": requirement("github")],
            consentVerifier: { _, _ in false }
        )

        let status = await orchestrator.run(.init(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        ))

        XCTAssertEqual(status, .failed)
        let githubCalls = await github.callCount()
        XCTAssertEqual(githubCalls, 0)
        XCTAssertNil(try history.cursor())
        XCTAssertEqual(try history.recentEntries(limit: 1).first?.errorKind, HistoryErrorKind.consentRequired)
    }

    func test_acceptedConsentDelivers() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": requirement("github")],
            consentVerifier: { _, categories in categories == ["steps"] }
        )

        let status = await orchestrator.run(.init(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        ))

        XCTAssertEqual(status, .success)
        let githubCalls = await github.callCount()
        XCTAssertEqual(githubCalls, 1)
    }

    func test_bothSelectedWithOnlyOneConsentDeliversNeither() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let telegram = RecordingSink(id: "telegram")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github, telegram],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": requirement("github"), "telegram": requirement("telegram")],
            consentVerifier: { requirement, _ in requirement.sinkID == "github" }
        )

        let status = await orchestrator.run(.init(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github", "telegram"]
        ))

        XCTAssertEqual(status, .failed)
        let githubCalls = await github.callCount()
        let telegramCalls = await telegram.callCount()
        XCTAssertEqual(githubCalls, 0)
        XCTAssertEqual(telegramCalls, 0)
    }

    func test_consentRevokedDuringHealthReadFailsClosedBeforeDelivery() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let verifier = ScriptedConsentVerifier([true, true, false])
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": requirement("github")],
            consentVerifier: { _, _ in await verifier.next() }
        )

        let status = await orchestrator.run(.init(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        ))

        XCTAssertEqual(status, .failed)
        let githubCalls = await github.callCount()
        XCTAssertEqual(githubCalls, 0)
        XCTAssertNil(try history.cursor())
        XCTAssertEqual(try history.recentEntries(limit: 1).first?.errorKind, HistoryErrorKind.consentRequired)
    }

    func test_revocationDuringFirstDeliveryStopsLaterDaysAndPreservesCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let sink = PausedFirstDeliverySink()
        let defaults = uniqueDefaults()
        let history = try HistoryStore.inMemory()
        let consent = HealthExportConsentStore(defaults: defaults)
        let required = requirement("github")
        consent.accept(required.scope(for: ["steps"]))
        let days = [
            makeDay(dayISO: "2026-04-08T00:00:00Z", unavailable: [], hasData: true),
            makeDay(dayISO: "2026-04-09T00:00:00Z", unavailable: [], hasData: true)
        ]
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [sink],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": required],
            consentVerifier: { requirement, categories in
                consent.hasCurrentConsent(for: requirement.scope(for: categories))
            },
            pipelineDaysOverride: { _, _, _, _ in days }
        )
        let run = Task { await orchestrator.run(.init(
            mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github"]
        )) }
        await sink.waitForFirstDelivery()
        consent.invalidate(.github)
        await sink.releaseFirstDelivery()

        let status = await run.value
        let calls = await sink.callCount()
        XCTAssertEqual(status, .failed)
        XCTAssertEqual(calls, 1)
        XCTAssertNil(try history.cursor())
        let entry = try XCTUnwrap(history.recentEntries(limit: 1).first)
        XCTAssertEqual(entry.errorKind, HistoryErrorKind.consentRequired)
        XCTAssertTrue(entry.errorMessage?.contains("in-flight") == true)
    }

    func test_networkBoundaryBlocksGitHubAndTelegramHealthRequestsUntilConsent() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsentBoundaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let github = GitHubSink(
            credentialProvider: StaticCredentialProvider(
                token: "fixture-token", owner: "octocat", repo: "health", branch: "main"
            ),
            session: session
        )
        let telegram = TelegramSink(
            credentials: TelegramCredentials(
                botToken: "fixture-token", chatID: "-1001234567890", verbosity: .standard
            ),
            session: session
        )
        let consent = HealthExportConsentStore(defaults: uniqueDefaults())
        let history = try HistoryStore.inMemory()
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github, telegram],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": requirement("github"), "telegram": requirement("telegram")],
            consentVerifier: { requirement, categories in
                consent.hasCurrentConsent(for: requirement.scope(for: categories))
            }
        )
        let request = ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github", "telegram"]
        )

        ConsentBoundaryURLProtocol.reset()
        let device = try await GitHubDeviceFlowClient(session: session, clientID: "fixture").startDeviceFlow()
        XCTAssertEqual(device.deviceCode, "device")
        let installations = try await GitHubInstallationPicker(session: session).loadInstallations(token: "fixture-token")
        XCTAssertEqual(installations.first?.account, "octocat")
        let (botData, _) = try await session.data(from: URL(string: "https://api.telegram.org/botfixture-token/getMe")!)
        XCTAssertTrue(String(decoding: botData, as: UTF8.self).contains("\"is_bot\":true"))
        let blockedStatus = await orchestrator.run(request)
        XCTAssertEqual(blockedStatus, .failed)
        let beforeConsent = ConsentBoundaryURLProtocol.captured.compactMap { $0.url?.path }
        XCTAssertEqual(beforeConsent.count, 3)
        XCTAssertTrue(beforeConsent.contains("/login/device/code"))
        XCTAssertTrue(beforeConsent.contains("/user/installations"))
        XCTAssertTrue(beforeConsent.contains { $0.hasSuffix("/getMe") })

        consent.accept(requirement("github").scope(for: ["steps"]))
        consent.accept(requirement("telegram").scope(for: ["steps"]))
        let approvedStatus = await orchestrator.run(request)
        XCTAssertEqual(approvedStatus, .success)
        let paths = ConsentBoundaryURLProtocol.captured.compactMap { $0.url?.path }
        XCTAssertTrue(paths.contains { $0.hasSuffix("/git/commits") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/git/refs/heads/main") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/sendMessage") })
        XCTAssertTrue(paths.contains { $0.hasSuffix("/sendDocument") })
    }

    func test_telegramRevokedAfterMessageNeverStartsDocumentUpload() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsentBoundaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let consent = HealthExportConsentStore(defaults: uniqueDefaults())
        let requirement = requirement("telegram")
        consent.accept(requirement.scope(for: ["steps"]))
        let telegram = TelegramSink(
            credentials: TelegramCredentials(botToken: "fixture-token", chatID: "-1001234567890", verbosity: .standard),
            session: session,
            authorizePayload: { consent.hasCurrentConsent(for: requirement.scope(for: ["steps"])) }
        )
        let history = try HistoryStore.inMemory()
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [telegram],
            historyStore: history,
            clock: { now },
            consentRequirements: ["telegram": requirement],
            consentVerifier: { requirement, categories in
                consent.hasCurrentConsent(for: requirement.scope(for: categories))
            }
        )
        ConsentBoundaryURLProtocol.reset(onRequest: { request in
            if request.url?.path.hasSuffix("/sendMessage") == true { consent.invalidate(.telegram) }
        })
        let status = await orchestrator.run(.init(
            mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["telegram"]
        ))
        XCTAssertEqual(status, .failed)
        let paths = ConsentBoundaryURLProtocol.captured.compactMap { $0.url?.path }
        XCTAssertTrue(paths.contains { $0.hasSuffix("/sendMessage") })
        XCTAssertFalse(paths.contains { $0.hasSuffix("/sendDocument") })
        XCTAssertNil(try history.cursor())
        XCTAssertEqual(try history.recentEntries(limit: 1).first?.errorKind, HistoryErrorKind.consentRequired)
    }

    func test_githubRevokedAfterRefLookupNeverStartsCommitWrites() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ConsentBoundaryURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let consent = HealthExportConsentStore(defaults: uniqueDefaults())
        let requirement = requirement("github")
        consent.accept(requirement.scope(for: ["steps"]))
        let github = GitHubSink(
            credentialProvider: StaticCredentialProvider(
                token: "fixture-token", owner: "octocat", repo: "health", branch: "main"
            ),
            session: session,
            authorizePayload: { consent.hasCurrentConsent(for: requirement.scope(for: ["steps"])) }
        )
        let history = try HistoryStore.inMemory()
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github],
            historyStore: history,
            clock: { now },
            consentRequirements: ["github": requirement],
            consentVerifier: { requirement, categories in
                consent.hasCurrentConsent(for: requirement.scope(for: categories))
            }
        )
        ConsentBoundaryURLProtocol.reset(onRequest: { request in
            if request.url?.path.hasSuffix("/git/ref/heads/main") == true {
                consent.invalidate(.github)
            }
        })
        let status = await orchestrator.run(.init(
            mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github"]
        ))
        XCTAssertEqual(status, .failed)
        let captured = ConsentBoundaryURLProtocol.captured
        XCTAssertTrue(captured.contains { $0.url?.path.hasSuffix("/git/ref/heads/main") == true })
        XCTAssertFalse(captured.contains { $0.httpMethod != "GET" })
        XCTAssertNil(try history.cursor())
        XCTAssertEqual(try history.recentEntries(limit: 1).first?.errorKind, HistoryErrorKind.consentRequired)
    }

    func test_webhookReferenceIsStoredInHistory() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let history = try HistoryStore.inMemory()
        let webhook = RecordingSink(id: "webhook", reference: "hooks.example.com · HTTP 202")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [webhook],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["webhook"]
        ))

        XCTAssertEqual(status, .success)
        let entry = try XCTUnwrap(try history.recentEntries(limit: 1).first)
        XCTAssertEqual(entry.sinks, ["webhook"])
        XCTAssertEqual(entry.webhookReference, "hooks.example.com · HTTP 202")
        XCTAssertNil(entry.telegramMessageReference)
    }

    func test_lastDayOnly_recordsSuccess_andAdvancesCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github", reference: "sha123", url: URL(string: "https://example.com/c"))
        let telegram = RecordingSink(id: "telegram", reference: "msg456")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github, telegram],
            historyStore: history,
            clock: { now }
        )

        let request = ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github", "telegram"]
        )
        let status = await orchestrator.run(request)

        XCTAssertEqual(status, .success)

        let cursor = try history.cursor()
        XCTAssertEqual(cursor, iso("2026-04-10T00:00:00Z"))

        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .success)
        XCTAssertEqual(entries[0].githubCommitSha, "sha123")
        XCTAssertEqual(entries[0].githubCommitURLString, "https://example.com/c")
        XCTAssertEqual(entries[0].telegramMessageReference, "msg456")
        XCTAssertEqual(entries[0].daysCovered, ["2026-04-09"])

        let githubCalls = await github.callCount()
        let telegramCalls = await telegram.callCount()
        XCTAssertGreaterThan(githubCalls, 0)
        XCTAssertGreaterThan(telegramCalls, 0)
    }

    func test_moreThanTenLastDayExports_allSucceedWithoutAnyPurchase() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let telegram = RecordingSink(id: "telegram")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: makePipeline(clockDate: now),
            sinks: [github, telegram],
            historyStore: history,
            clock: { now }
        )
        let request = ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github", "telegram"]
        )

        for runNumber in 1...12 {
            let status = await orchestrator.run(request)
            let githubCalls = await github.callCount()
            let telegramCalls = await telegram.callCount()
            XCTAssertEqual(status, .success, "run \(runNumber) should complete")
            XCTAssertEqual(githubCalls, runNumber)
            XCTAssertEqual(telegramCalls, runNumber)
        }

        let entries = try history.recentEntries(limit: 20)
        XCTAssertEqual(entries.count, 12)
        XCTAssertTrue(entries.allSatisfy { $0.status == .success && $0.daysCovered == ["2026-04-09"] })
        XCTAssertEqual(try history.cursor(), iso("2026-04-10T00:00:00Z"))
    }

    func test_sinkThrowsSessionExpired_recordsErrorKind() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let expiring = SessionExpiredSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [expiring],
            historyStore: history,
            clock: { now }
        )

        let request = ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        )
        let status = await orchestrator.run(request)

        XCTAssertEqual(status, .failed)

        let entries = try history.recentEntries(limit: 1)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .failed)
        XCTAssertEqual(entries[0].errorKind, HistoryErrorKind.sessionExpired)
    }

    func test_sinkThrowsOtherError_doesNotSetSessionExpiredKind() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let broken = ThrowingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [broken],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .failed)
        let entries = try history.recentEntries(limit: 1)
        XCTAssertNil(entries[0].errorKind)
    }

    func test_sinkThrows_recordsFailure_andCursorUnchanged() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let broken = ThrowingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [broken],
            historyStore: history,
            clock: { now }
        )

        let request = ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps"],
            enabledSinkIds: ["github"]
        )
        let status = await orchestrator.run(request)

        XCTAssertEqual(status, .failed)

        let cursor = try history.cursor()
        XCTAssertNil(cursor)

        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .failed)
        XCTAssertNotNil(entries[0].errorMessage)
    }

    func test_emptyActiveSinks_failsWithoutAdvancingCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["unknown"]
            )
        )

        XCTAssertEqual(status, .failed)
        let cursor = try history.cursor()
        XCTAssertNil(cursor)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 0)
    }

    func test_emptyEnabledCategories_failsWithoutAdvancingCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: [],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .failed)
        let cursor = try history.cursor()
        XCTAssertNil(cursor)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 0)
    }

    func test_lastNDays_exportsWithoutPurchase_andDoesNotAdvanceCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastNDays(7),
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .success)
        let cursor = try history.cursor()
        XCTAssertNil(cursor)
    }

    func test_range_exportsWithoutPurchase_andDoesNotAdvanceCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                // Covers makePipeline's sample (2026-04-09T18:00) — an empty
                // range window is now a failed run, tested separately.
                mode: .range(from: iso("2026-04-09T00:00:00Z"), to: iso("2026-04-10T00:00:00Z")),
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .success)
        let cursor = try history.cursor()
        XCTAssertNil(cursor)
    }

    func test_run_emitsExpectedProgressSequence_for2Categories1Day() async throws {
        let harness = try await OrchestratorTestHarness.makeWith(
            enabledCategoryIds: ["cat0", "cat1"],
            windowDays: 1
        )

        let captured = ActorIsolatedEvents()
        let handler: RunProgressHandler = { event in
            await captured.append(event)
        }

        let status = await harness.orchestrator.run(harness.request, progress: handler)
        XCTAssertEqual(status, .success)

        let events = await captured.events
        let kinds = events.map { caseKind(of: $0) }
        XCTAssertEqual(
            kinds,
            [
                "fetching",
                "readingSummary", "readingSummary",
                "startingSamplesFetch",
                "readingSamples", "readingSamples",
                "serializing",
                "delivering",
                "finished"
            ]
        )
        XCTAssertEqual(events.filter { caseKind(of: $0) == "readingSummary" }.count, 2,
                       "expected one .readingSummary per category (2 enabled)")
        XCTAssertEqual(events.filter { caseKind(of: $0) == "readingSamples" }.count, 2,
                       "expected one .readingSamples per category (2 enabled)")
    }

    private func caseKind(of event: RunProgress) -> String {
        switch event {
        case .fetching: return "fetching"
        case .readingSummary: return "readingSummary"
        case .startingSamplesFetch: return "startingSamplesFetch"
        case .readingSamples: return "readingSamples"
        case .serializing: return "serializing"
        case .delivering: return "delivering"
        case .retrying: return "retrying"
        case .finished: return "finished"
        }
    }

    func test_allCategoriesReadableButEmpty_exportsHonestly() async throws {
        // HealthKit returns [] WITHOUT an error when access is denied, so an
        // empty-but-no-error window is indistinguishable from a genuinely quiet
        // day (or a fresh device — the App Review case). We cannot infer denial
        // from emptiness, so a readable empty day is exported honestly rather
        // than failed with a false "check permissions" message.
        let now = iso("2026-04-10T12:00:00Z")
        let emptySteps = StubCategory(id: "steps", samples: [])
        let pipeline = SnapshotPipeline(
            registry: CategoryRegistry(categories: [emptySteps]),
            timezone: timezone,
            deviceName: "iPhone Test",
            appVersion: "1.0.0",
            clock: { now }
        )
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .success, "an empty-but-readable day is a truthful export, not a failure")
        let calls = await github.callCount()
        XCTAssertEqual(calls, 1, "the empty day is still delivered")
    }

    func test_allCategoriesUnreadable_failsWithHonestErrorAndNoSideEffects() async throws {
        // Positive error evidence: every enabled category THROWS, so it lands
        // in unavailableCategories. That is a real failure (transient HealthKit
        // error or denial) — fail without delivering or advancing the cursor,
        // and name the categories rather than asserting a cause.
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = SnapshotPipeline(
            registry: CategoryRegistry(categories: [ThrowingCategory(id: "steps"), ThrowingCategory(id: "sleep")]),
            timezone: timezone,
            deviceName: "iPhone Test",
            appVersion: "1.0.0",
            clock: { now }
        )
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: ["steps", "sleep"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .failed)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 0, "must not deliver when nothing is readable")
        XCTAssertNil(try history.cursor(), "must not advance the cursor")
        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.errorKind, HistoryErrorKind.healthDataUnreadable)
        XCTAssertTrue(entries.first?.errorMessage?.contains("steps") ?? false, "message names the unreadable categories")
    }

    func test_partiallyUnreadable_stillExportsTheReadableCategories() async throws {
        // One category errors, another has data → the window is not fully
        // unreadable, so it exports (the failed one is noted in summary.json).
        let now = iso("2026-04-10T12:00:00Z")
        let sampleStart = now.addingTimeInterval(-18 * 60 * 60)
        let steps = StubCategory(id: "steps", samples: [
            QuantitySampleDTO(categoryID: "steps", startDate: sampleStart, endDate: sampleStart.addingTimeInterval(60), value: 100, unit: "count", sourceName: "iPhone", sourceBundleID: "com.apple.health")
        ])
        let pipeline = SnapshotPipeline(
            registry: CategoryRegistry(categories: [steps, ThrowingCategory(id: "sleep")]),
            timezone: timezone,
            deviceName: "iPhone Test",
            appVersion: "1.0.0",
            clock: { now }
        )
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps", "sleep"], enabledSinkIds: ["github"])
        )

        XCTAssertEqual(status, .success)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 1)
    }

    // The real HealthKit pipeline marks a category unavailable for the whole
    // window at once, so a window where only SOME days are fully unreadable
    // cannot be produced through real categories. Build the days directly and
    // feed them via `pipelineDaysOverride` to exercise the partition.
    private func makeDay(dayISO: String, unavailable: [String], hasData: Bool) -> SnapshotPipelineDay {
        var snapshot = DailySnapshot(
            date: iso(dayISO),
            timezone: timezone.identifier,
            generatedAt: iso(dayISO),
            deviceName: "iPhone Test",
            appVersion: "1.0.0"
        )
        snapshot.unavailableCategories = unavailable
        if hasData {
            snapshot.summaries["steps"] = SummaryFragment(metrics: ["count": .int(1)], unit: "count")
        }
        return SnapshotPipelineDay(snapshot: snapshot, files: [], samplesByCategory: [:])
    }

    func test_partialWindow_deliversOnlyReadableDays_andRecordsThoseDaysCovered() async throws {
        // Multi-day backfill where the middle day is fully unreadable (a
        // transient HealthKit error): it must be dropped, not published as an
        // empty commit. The readable days on either side are delivered honestly.
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let days = [
            makeDay(dayISO: "2026-04-07T00:00:00Z", unavailable: [], hasData: true),
            makeDay(dayISO: "2026-04-08T00:00:00Z", unavailable: ["steps"], hasData: false),
            makeDay(dayISO: "2026-04-09T00:00:00Z", unavailable: [], hasData: true)
        ]

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            pipelineDaysOverride: { _, _, _, _ in days }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .range(from: iso("2026-04-07T00:00:00Z"), to: iso("2026-04-10T00:00:00Z")),
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .success, "a partial window still succeeds on the readable days")

        let deliveredDates = await github.dates()
        XCTAssertEqual(
            deliveredDates,
            [iso("2026-04-07T00:00:00Z"), iso("2026-04-09T00:00:00Z")],
            "only the two readable days are delivered; the unreadable middle day is dropped"
        )

        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .success)
        XCTAssertEqual(
            entries[0].daysCovered,
            ["2026-04-07", "2026-04-09"],
            "daysCovered reflects only the delivered readable days, not the skipped one"
        )
    }

    func test_allDaysUnreadable_viaOverride_failsWithoutDelivering() async throws {
        // Companion to the partial-window test: when EVERY day is fully
        // unreadable the whole run fails (healthDataUnreadable), nothing is
        // delivered, and the cursor is not advanced.
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let days = [
            makeDay(dayISO: "2026-04-08T00:00:00Z", unavailable: ["steps"], hasData: false),
            makeDay(dayISO: "2026-04-09T00:00:00Z", unavailable: ["steps"], hasData: false)
        ]

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            pipelineDaysOverride: { _, _, _, _ in days }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .range(from: iso("2026-04-08T00:00:00Z"), to: iso("2026-04-10T00:00:00Z")),
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .failed)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 0, "an all-unreadable window delivers nothing")
        XCTAssertNil(try history.cursor())
        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].errorKind, HistoryErrorKind.healthDataUnreadable)
    }

    func test_rangeEntirelyWithinToday_failsAsEmptyNotPhantomSuccess() async throws {
        // Regression for the phantom-success bug: a same-day range resolves to
        // zero completed days; it must record a .failed/emptyRange entry, not
        // run the delivery loop zero times and report success.
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .range(from: iso("2026-04-10T06:00:00Z"), to: iso("2026-04-10T09:00:00Z")),
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .failed)
        let rangeCalls = await github.callCount()
        XCTAssertEqual(rangeCalls, 0, "phantom success must not happen — nothing to deliver")
        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.errorKind, HistoryErrorKind.emptyRange)
    }

    func test_deviceLockedMidRun_failsBeforeDeliveryWithoutSideEffects() async throws {
        // The lock check at run start passes, but the device locks during the
        // (now per-day, minutes-long) HealthKit reads. The post-pipeline
        // re-check must catch it before any delivery or cursor advance.
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let gate = ProtectedDataGate([true, false])  // unlocked at start, locked after fetch
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            isProtectedDataAvailable: { await gate.next() }
        )

        let status = await orchestrator.run(
            ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github"])
        )

        XCTAssertEqual(status, .failed)
        let lockCalls = await github.callCount()
        XCTAssertEqual(lockCalls, 0, "must not deliver after a mid-run lock")
        XCTAssertNil(try history.cursor(), "must not advance the cursor")
        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.errorKind, HistoryErrorKind.deviceLocked)
    }

    func test_partialData_stillExportsNormally() async throws {
        // The guard is all-or-nothing: a window with ANY readable data
        // exports as usual (makePipeline's steps category has one sample).
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .success)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 1)
    }

    func test_deviceLocked_skipsDeliveryAndDoesNotAdvanceCursor() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")

        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            isProtectedDataAvailable: { false }
        )

        let status = await orchestrator.run(
            ExportRequest(
                mode: .lastDayOnly,
                enabledCategoryIds: ["steps"],
                enabledSinkIds: ["github"]
            )
        )

        XCTAssertEqual(status, .failed)
        let calls = await github.callCount()
        XCTAssertEqual(calls, 0, "must not deliver an empty export while the device is locked")
        let cursor = try history.cursor()
        XCTAssertNil(cursor, "locked-device run must not advance the cursor")
        let entries = try history.recentEntries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].status, .failed)
        XCTAssertEqual(entries[0].errorKind, HistoryErrorKind.deviceLocked)
    }

    func test_limitedHistoryOnFirstCheckStopsBeforeCollectionOrAnySideEffect() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let validator = ScriptedHistoryValidator([.failure(.limitedHistory)])
        let pipelineCalls = InvocationCounter()
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            historyValidator: { from, to, ids in
                try await validator.validate(from: from, to: to, enabledCategoryIds: ids)
            },
            pipelineDaysOverride: { _, _, _, _ in
                await pipelineCalls.increment()
                return []
            }
        )

        let status = await orchestrator.run(
            ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github"])
        )

        XCTAssertEqual(status, .failed)
        let collectionCount = await pipelineCalls.count
        let sinkCount = await github.callCount()
        XCTAssertEqual(collectionCount, 0)
        XCTAssertEqual(sinkCount, 0)
        XCTAssertNil(try history.cursor())
        let entry = try XCTUnwrap(history.recentEntries(limit: 1).first)
        XCTAssertEqual(entry.errorKind, HistoryErrorKind.limitedHealthHistory)
        XCTAssertEqual(entry.errorMessage, HealthHistoryCoverageError.limitedHistory.userMessage)
        XCTAssertFalse(entry.errorMessage?.contains("steps") ?? true)
        XCTAssertFalse(entry.errorMessage?.contains("2026-") ?? true)
    }

    func test_historyLookupFailureFailsClosedBeforeCollection() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let validator = ScriptedHistoryValidator([.failure(.checkFailed)])
        let pipelineCalls = InvocationCounter()
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            historyValidator: { from, to, ids in
                try await validator.validate(from: from, to: to, enabledCategoryIds: ids)
            },
            pipelineDaysOverride: { _, _, _, _ in
                await pipelineCalls.increment()
                return []
            }
        )

        let status = await orchestrator.run(
            ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github"])
        )

        XCTAssertEqual(status, .failed)
        let collectionCount = await pipelineCalls.count
        let sinkCount = await github.callCount()
        XCTAssertEqual(collectionCount, 0)
        XCTAssertEqual(sinkCount, 0)
        let entry = try XCTUnwrap(history.recentEntries(limit: 1).first)
        XCTAssertEqual(entry.errorKind, HistoryErrorKind.healthHistoryCheckFailed)
        XCTAssertEqual(entry.errorMessage, HealthHistoryCoverageError.checkFailed.userMessage)
    }

    func test_historyBecomesLimitedAfterCollectionStopsBeforeFirstSinkAndPreservesState() async throws {
        let now = iso("2026-04-10T12:00:00Z")
        let pipeline = makePipeline(clockDate: now)
        let history = try HistoryStore.inMemory()
        let github = RecordingSink(id: "github")
        let validator = ScriptedHistoryValidator([.success(()), .failure(.limitedHistory)])
        let day = makeDay(dayISO: "2026-04-09T00:00:00Z", unavailable: [], hasData: true)
        let orchestrator = Orchestrator(
            windowResolver: ExportWindowResolver(timezone: timezone),
            pipeline: pipeline,
            sinks: [github],
            historyStore: history,
            clock: { now },
            historyValidator: { from, to, ids in
                try await validator.validate(from: from, to: to, enabledCategoryIds: ids)
            },
            pipelineDaysOverride: { _, _, _, _ in [day] }
        )

        let status = await orchestrator.run(
            ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github"])
        )

        XCTAssertEqual(status, .failed)
        let validationCount = await validator.count
        let sinkCount = await github.callCount()
        XCTAssertEqual(validationCount, 2)
        XCTAssertEqual(sinkCount, 0)
        XCTAssertNil(try history.cursor())
        XCTAssertEqual(try history.recentEntries(limit: 1).first?.errorKind, HistoryErrorKind.limitedHealthHistory)
    }
}
