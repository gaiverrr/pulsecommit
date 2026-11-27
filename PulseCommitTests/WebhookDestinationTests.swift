import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class WebhookDestinationTests: XCTestCase {
    private final class StubProtocol: URLProtocol {
        nonisolated(unsafe) static var status = 200
        nonisolated(unsafe) static var requests: [URLRequest] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            Self.requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                           httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private let secretPath = "/api/webhook/ha-secret-path-123"
    private let token = "tok_SECRET_value_0123456789"

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "WebhookDestinationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func configuration(
        _ url: String = "https://hooks.example.com/api/webhook/ha-secret-path-123",
        token: String? = nil,
        header: String = "Authorization"
    ) throws -> WebhookConfiguration {
        try WebhookConfiguration(endpoint: URL(string: url)!, token: token, tokenHeader: header)
    }

    private func identity(_ configuration: WebhookConfiguration) -> HealthExportDestinationIdentity {
        HealthExportDestinationIdentity(webhook: configuration.consentIdentity)
    }

    private func makeStubSession(status: Int) -> URLSession {
        StubProtocol.requests = []
        StubProtocol.status = status
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeContainer(
        secrets: any SecretsStore = InMemorySecretsStore(),
        defaults: UserDefaults? = nil
    ) -> AppContainer {
        let defaults = defaults ?? ephemeralDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        let healthStore = HealthStoreClient()
        return AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: try! HistoryStore.inMemory(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            consentStore: HealthExportConsentStore(defaults: defaults),
            automaticWorkoutConsentStore: AutomaticWorkoutConsentStore(defaults: defaults),
            orchestratorFactory: AppContainer.defaultOrchestratorFactory(
                runGate: ExportRunGate(),
                healthStore: healthStore
            )
        )
    }

    private func snapshot() -> DailySnapshot {
        DailySnapshot(
            date: Date(timeIntervalSince1970: 1_778_716_800),
            timezone: "UTC",
            generatedAt: Date(timeIntervalSince1970: 1_778_800_000),
            deviceName: "iPhone",
            appVersion: "1.0.2"
        )
    }

    private func files() -> [FileEntry] {
        [
            FileEntry(path: "2026-05-14/summary.json", data: Data("{\"schema_version\":\"1.0\"}".utf8)),
            FileEntry(path: "2026-05-14/summary.md", data: Data("# Pulse Commit".utf8))
        ]
    }

    func test_consentIdentityChangesWithEveryURLPart() throws {
        let base = identity(try configuration("https://hooks.example.com/a"))
        XCTAssertNotEqual(base, identity(try configuration("https://other.example.com/a")))
        XCTAssertNotEqual(base, identity(try configuration("https://hooks.example.com:8443/a")))
        XCTAssertNotEqual(base, identity(try configuration("https://hooks.example.com/b")))
        XCTAssertEqual(base.kind, .webhook)
    }

    func test_consentIdentityIgnoresTokenAndHeader() throws {
        let base = identity(try configuration("https://hooks.example.com/a", token: "one"))
        XCTAssertEqual(base, identity(try configuration("https://hooks.example.com/a", token: "two")))
        XCTAssertEqual(base, identity(try configuration("https://hooks.example.com/a", token: nil)))
        XCTAssertEqual(base, identity(try configuration("https://hooks.example.com/a", token: "two", header: "X-Gitlab-Token")))
    }

    func test_consentRecordAndDisplayNeverContainPathOrToken() throws {
        let defaults = ephemeralDefaults()
        let store = HealthExportConsentStore(defaults: defaults)
        let scope = HealthExportConsentScope(
            destination: identity(try configuration(token: token)),
            enabledCategoryIds: ["steps"]
        )
        store.accept(scope)

        let data = try XCTUnwrap(defaults.data(forKey: HealthExportConsentStore.storageKey(for: .webhook)))
        let encoded = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(encoded.contains("ha-secret-path"))
        XCTAssertFalse(encoded.contains(token))
        XCTAssertTrue(store.hasCurrentConsent(for: scope))
        XCTAssertEqual(scope.destination.displayName, "hooks.example.com")
        XCTAssertFalse(scope.id.contains("ha-secret-path"))
    }

    func test_disclosureUsesSpecTextWithHost() throws {
        let scope = HealthExportConsentScope(
            destination: identity(try configuration()),
            enabledCategoryIds: ["steps"]
        )
        let disclosure = HealthExportDisclosure(scope: scope)
        XCTAssertEqual(disclosure.target, "hooks.example.com")
        XCTAssertEqual(disclosure.webhookNotice, [
            "Pulse Commit will send the Health categories you selected to hooks.example.com over HTTPS each time you export to this destination.",
            "Pulse Commit does not run this server. Whoever operates it can read, keep and share what it receives. Pulse Commit cannot delete data after it is sent.",
            "If this address belongs to an AI agent or an automation service, that service will process your Health data."
        ])
    }

    func test_settingsRoundTripThroughSecretsOnlyAndClear() async throws {
        let defaults = ephemeralDefaults()
        let secrets = InMemorySecretsStore()
        let container = makeContainer(secrets: secrets, defaults: defaults)

        let saved = try await container.saveWebhookSettings(
            endpoint: "https://hooks.example.com\(secretPath)",
            token: token,
            tokenHeader: "X-Gitlab-Token"
        )
        XCTAssertEqual(saved.host, "hooks.example.com")

        let stored = await container.storedWebhookSettings()
        XCTAssertEqual(stored, WebhookSettingsDraft(
            endpoint: "https://hooks.example.com\(secretPath)",
            token: token,
            tokenHeader: "X-Gitlab-Token"
        ))
        let current = await container.currentWebhookConfiguration()
        XCTAssertEqual(current, saved)

        let persisted = defaults.dictionaryRepresentation().description
        XCTAssertFalse(persisted.contains("ha-secret-path"))
        XCTAssertFalse(persisted.contains(token))

        await container.clearWebhookSettings()
        let cleared = await container.storedWebhookSettings()
        XCTAssertNil(cleared)
        for key in WebhookSecretKeys.all {
            let value = try await secrets.get(key)
            XCTAssertNil(value)
        }
    }

    func test_resetSecretKeysIncludeWebhookKeys() {
        for key in WebhookSecretKeys.all {
            XCTAssertTrue(AppContainer.resettableSecretKeys.contains(key))
        }
        XCTAssertTrue(AppContainer.resettableSecretKeys.contains("tg_bot_token"))
        XCTAssertTrue(AppContainer.resettableSecretKeys.contains(KeychainTokenVault.storageKey))
    }

    func test_invalidSettingsAreRejectedWithoutWriting() async throws {
        let secrets = InMemorySecretsStore()
        let container = makeContainer(secrets: secrets)
        do {
            _ = try await container.saveWebhookSettings(endpoint: "http://hooks.example.com/x", token: "", tokenHeader: "Authorization")
            XCTFail("expected validation error")
        } catch let error as WebhookConfigurationError {
            XCTAssertEqual(error, .insecureScheme)
        }
        let stored = await container.storedWebhookSettings()
        XCTAssertNil(stored)
    }

    func test_emptyTokenIsNotStored() async throws {
        let secrets = InMemorySecretsStore()
        let container = makeContainer(secrets: secrets)
        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: "  ", tokenHeader: "Authorization")
        let storedToken = try await secrets.get(WebhookSecretKeys.token)
        XCTAssertNil(storedToken)
        let stored = await container.storedWebhookSettings()
        XCTAssertEqual(stored?.token, "")
    }

    private func configureGitHub(_ container: AppContainer) {
        container.preferences.githubOwner = "octocat"
        container.preferences.githubRepo = "health"
        container.preferences.githubBranch = "main"
        container.preferences.githubSubdir = ""
    }

    private func acceptWebhookConsent(_ container: AppContainer) async throws {
        let maybeScope = await container.currentConsentScope(for: .webhook)
        let scope = try XCTUnwrap(maybeScope)
        let accepted = await container.acceptConsentIfCurrent(scope)
        XCTAssertTrue(accepted)
    }

    func test_savedWebhookJoinsExportsOnlyOnceEnrolled() async throws {
        let container = makeContainer()
        container.preferences.enabledCategoryIds = ["steps"]

        var orchestrator = await container.orchestratorFactory()
        var sinkIDs = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIDs, [])

        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization")
        orchestrator = await container.orchestratorFactory()
        sinkIDs = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIDs, [])
        var configured = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(configured, [])

        container.preferences.webhookExportEnabled = true
        orchestrator = await container.orchestratorFactory()
        sinkIDs = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIDs, ["webhook"])
        configured = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(configured, ["webhook"])
        var ready = await container.webhookExportIsReady()
        XCTAssertFalse(ready)

        try await acceptWebhookConsent(container)
        ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)
        let request = ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["webhook"])
        orchestrator = await container.orchestratorFactory()
        let consented = await orchestrator.hasCurrentConsent(for: request)
        XCTAssertTrue(consented)

        container.preferences.webhookExportEnabled = false
        orchestrator = await container.orchestratorFactory()
        sinkIDs = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIDs, [])
        configured = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(configured, [])
    }

    func test_tokenRotationKeepsConsentButURLChangeDoesNot() async throws {
        let container = makeContainer()
        container.preferences.enabledCategoryIds = ["steps"]
        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: "one", tokenHeader: "Authorization")
        try await acceptWebhookConsent(container)

        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: "two", tokenHeader: "Authorization")
        var ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)

        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/y", token: "two", tokenHeader: "Authorization")
        ready = await container.webhookExportIsReady()
        XCTAssertFalse(ready)
    }

    func test_staleWebhookConsentIsReportedNotSkipped() async throws {
        let container = makeContainer()
        container.preferences.enabledCategoryIds = ["steps"]
        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization")
        try await acceptWebhookConsent(container)
        container.preferences.enabledCategoryIds = ["steps", "sleep"]

        let ids = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(ids, ["webhook"])
        let orchestrator = await container.orchestratorFactory()
        let missing = await orchestrator.missingConsentScopes(for: ExportRequest(
            mode: .lastDayOnly,
            enabledCategoryIds: ["steps", "sleep"],
            enabledSinkIds: ids
        ))
        XCTAssertEqual(missing.map(\.destination.kind), [.webhook])
        XCTAssertEqual(missing.first?.enabledCategoryIds, ["sleep", "steps"])

        let viewModel = HomeViewModel(runRequest: { _, _ in .success }, enabledCategoryIds: { [] }, enabledSinkIds: { [] })
        let home = HomeView(
            viewModel: viewModel,
            deviceName: "iPhone",
            appVersion: "1.0.2",
            timezoneAbbreviation: "UTC",
            recentCommits: [],
            recentCommitsBranchHint: nil,
            healthPermissionRequestCompleted: true,
            githubConfigured: ids.contains("github"),
            telegramConfigured: ids.contains("telegram"),
            webhookConfigured: ids.contains("webhook")
        )
        XCTAssertFalse(home.isEmptyState)
    }

    func test_githubAndStaleWebhookRunFailsWithConsentRequired() async throws {
        let container = makeContainer()
        configureGitHub(container)
        container.preferences.enabledCategoryIds = ["steps"]
        container.consentStore.accept(HealthExportConsentScope(
            destination: .github(owner: "octocat", repo: "health", branch: "main", subdir: ""),
            enabledCategoryIds: ["steps"]
        ))
        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization")
        container.preferences.webhookExportEnabled = true

        let request = ExportRequest(mode: .lastDayOnly, enabledCategoryIds: ["steps"], enabledSinkIds: ["github", "webhook"])
        let orchestrator = await container.orchestratorFactory()
        let missing = await orchestrator.missingConsentScopes(for: request)
        XCTAssertEqual(missing.map(\.destination.kind), [.webhook])

        let status = await orchestrator.run(request)

        XCTAssertEqual(status, .failed)
        let entry = try XCTUnwrap(try container.history.recentEntries(limit: 1).first)
        XCTAssertEqual(entry.errorKind, HistoryErrorKind.consentRequired)
    }

    func test_shortcutWithStaleWebhookConsentThrowsConsentRequired() async throws {
        let container = makeContainer()
        container.preferences.enabledCategoryIds = ["steps"]
        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization")
        try await acceptWebhookConsent(container)
        container.preferences.webhookExportEnabled = false
        container.preferences.webhookExportEnabled = true

        do {
            _ = try await IntentRunner.run(mode: .lastDayOnly, container: container)
            XCTFail("expected consentRequired")
        } catch let error as IntentError {
            guard case .consentRequired = error else {
                return XCTFail("expected consentRequired, got \(error)")
            }
        }
    }

    func test_leavingWithInvalidChangedURLPausesWebhook() async throws {
        let container = makeContainer()
        container.preferences.enabledCategoryIds = ["steps"]
        _ = try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization")
        try await acceptWebhookConsent(container)
        let stored = await container.storedWebhookSettings()
        let generation = container.resetGeneration

        container.applyWebhookDraftOnLeave(
            WebhookSettingsDraft(endpoint: "http://other.example.com/x", token: token, tokenHeader: "Authorization"),
            stored: stored,
            generation: generation
        )
        XCTAssertTrue(container.preferences.webhookPausedByInvalidEdit)
        await container.webhookWritesSettled()
        let kept = await container.storedWebhookSettings()
        XCTAssertEqual(kept?.endpoint, "https://hooks.example.com/x")
        let configured = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(configured, [])
    }

    func test_invalidChangedDraftIsDetectedWithoutKeychain() {
        let stored = WebhookSettingsDraft(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization")
        func draft(_ endpoint: String, header: String = "Authorization", token: String? = nil) -> WebhookSettingsDraft {
            WebhookSettingsDraft(endpoint: endpoint, token: token ?? self.token, tokenHeader: header)
        }
        XCTAssertTrue(draft("http://other.example.com/x").isInvalidChange(from: stored))
        XCTAssertTrue(draft(stored.endpoint, header: "Bad Header").isInvalidChange(from: stored))
        XCTAssertTrue(draft(stored.endpoint, token: "Bearer abc").isInvalidChange(from: stored))
        XCTAssertFalse(draft("https://other.example.com/x").isInvalidChange(from: stored))
        XCTAssertFalse(draft(" ").isInvalidChange(from: stored))
        XCTAssertFalse(draft("http://other.example.com/x").isInvalidChange(from: nil))
    }

    func test_leavingWithValidOrEmptyDraftSavesOrClears() async throws {
        let container = makeContainer()
        container.applyWebhookDraftOnLeave(
            WebhookSettingsDraft(endpoint: "https://hooks.example.com/x", token: token, tokenHeader: "Authorization"),
            stored: nil,
            generation: container.resetGeneration
        )
        await container.webhookWritesSettled()
        var stored = await container.storedWebhookSettings()
        XCTAssertEqual(stored?.token, token)

        container.applyWebhookDraftOnLeave(
            WebhookSettingsDraft(endpoint: " ", token: token, tokenHeader: "Authorization"),
            stored: stored,
            generation: container.resetGeneration
        )
        await container.webhookWritesSettled()
        stored = await container.storedWebhookSettings()
        XCTAssertNil(stored)
    }

    func test_destinationSinkReportsHostAndStatusOnly() async throws {
        let configuration = try configuration(token: token)
        let sink = WebhookDestinationSink(sink: WebhookSink(
            configuration: configuration,
            session: makeStubSession(status: 202)
        ))
        XCTAssertEqual(sink.id, "webhook")

        let result = try await sink.deliver(snapshot: snapshot(), files: files(), onAttempt: nil)

        XCTAssertEqual(result, .success(reference: "hooks.example.com · HTTP 202", url: nil))
        XCTAssertEqual(StubProtocol.requests.count, 1)
    }

    func test_destinationSinkErrorNamesHostWithoutPathOrToken() async throws {
        let sink = WebhookDestinationSink(sink: WebhookSink(
            configuration: try configuration(token: token),
            session: makeStubSession(status: 401)
        ))
        do {
            _ = try await sink.deliver(snapshot: snapshot(), files: files(), onAttempt: nil)
            XCTFail("expected failure")
        } catch {
            let text = error.localizedDescription
            XCTAssertEqual(text, "webhook hooks.example.com: Endpoint returned HTTP 401. Check the token.")
            XCTAssertFalse(text.contains("ha-secret-path"))
            XCTAssertFalse(text.contains(token))
        }
    }

    func test_destinationSinkPassesConsentErrorsThrough() async throws {
        let sink = WebhookDestinationSink(sink: WebhookSink(
            configuration: try configuration(token: token),
            session: makeStubSession(status: 200),
            authorizePayload: { false }
        ))
        do {
            _ = try await sink.deliver(snapshot: snapshot(), files: files(), onAttempt: nil)
            XCTFail("expected failure")
        } catch {
            XCTAssertTrue(error is HealthExportAuthorizationError)
        }
        XCTAssertTrue(StubProtocol.requests.isEmpty)
    }

    func test_historyRowShowsHostAndStatusOnly() {
        let success = HistoryEntrySnapshot(
            id: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            status: .success,
            sinks: ["webhook"],
            daysCovered: ["2026-05-14"],
            webhookReference: "hooks.example.com · HTTP 200"
        )
        let row = HistoryRowModel.from(snapshot: success)
        XCTAssertEqual(row.sinkBadges, [.init(label: "hooks.example.com · HTTP 200", ok: true, kind: "webhook")])

        let failed = HistoryEntrySnapshot(
            id: UUID(),
            startedAt: Date(),
            finishedAt: Date(),
            status: .failed,
            sinks: ["webhook"],
            daysCovered: ["2026-05-14"],
            errorMessage: "sink failed: webhook hooks.example.com: Endpoint returned HTTP 404. Check the URL."
        )
        let failedRow = HistoryRowModel.from(snapshot: failed)
        XCTAssertEqual(failedRow.summary, "sink failed: webhook hooks.example.com: Endpoint returned HTTP 404. Check the URL.")
        XCTAssertEqual(failedRow.sinkBadges, [.init(label: "webhook", ok: false, kind: "webhook")])

        for model in [row, failedRow] {
            let rendered = ([model.summary] + model.sinkBadges.map(\.label)).joined(separator: " ")
            XCTAssertFalse(rendered.contains("/api/"))
            XCTAssertFalse(rendered.contains(token))
        }
    }

    func test_draftValidationShowsConfigurationErrorMessages() {
        XCTAssertNil(WebhookSettingsDraft.empty.validationMessage)
        XCTAssertEqual(
            WebhookSettingsDraft(endpoint: "http://hooks.example.com/x", token: "", tokenHeader: "Authorization").validationMessage,
            WebhookConfigurationError.insecureScheme.localizedDescription
        )
        XCTAssertEqual(
            WebhookSettingsDraft(endpoint: "https://hooks.example.com/x", token: "", tokenHeader: "Content-Type").validationMessage,
            WebhookConfigurationError.reservedHeaderName.localizedDescription
        )
        XCTAssertNil(WebhookSettingsDraft(endpoint: "https://hooks.example.com/x", token: "", tokenHeader: "").validationMessage)
    }

    func test_tokenFormattingNeverRevealsWholeToken() {
        XCTAssertEqual(WebhookTokenFormatting.headerPreview(header: "Authorization"), "Sent as Authorization: Bearer <token>")
        XCTAssertEqual(WebhookTokenFormatting.headerPreview(header: "X-Gitlab-Token"), "Sent as X-Gitlab-Token: <token>")
        let masked = WebhookTokenFormatting.masked(token)
        XCTAssertFalse(masked.contains(token))
        XCTAssertTrue(masked.hasSuffix("6789"))
        XCTAssertFalse(WebhookTokenFormatting.payloadPreview(header: "Authorization", hasToken: true).contains(token))
        XCTAssertEqual(WebhookTokenFormatting.accessibilityLabel(token: token, revealed: false), "Token, hidden, ends in 6789")
        XCTAssertEqual(WebhookTokenFormatting.accessibilityLabel(token: "", revealed: false), "Token, none")
    }

    func test_preferencesResetClearsWebhookToggle() {
        let defaults = ephemeralDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        XCTAssertFalse(preferences.webhookExportEnabled)
        preferences.webhookExportEnabled = true
        preferences.webhookPausedByInvalidEdit = true
        preferences.reset()
        XCTAssertFalse(preferences.webhookExportEnabled)
        XCTAssertFalse(preferences.webhookPausedByInvalidEdit)
    }
}
