import Combine
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class WebhookConsentReviewTests: XCTestCase {
    private let urlA = "https://hooks.example.com/a"
    private let urlB = "https://other.example.com/b"
    private let tokenA = "token-for-receiver-a"
    private let tokenB = "token-for-receiver-b"

    private final class ScriptedSecretsStore: SecretsStore, @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: String] = [:]
        private var failingGets: [String: Int] = [:]
        private var failingSets: [String: Int] = [:]
        private var log: [String] = []

        func get(_ key: String) async throws -> String? {
            try lock.withLock {
                if let remaining = failingGets[key], remaining > 0 {
                    failingGets[key] = remaining - 1
                    throw KeychainError.unexpectedStatus(-34018)
                }
                return storage[key]
            }
        }

        func set(_ value: String?, for key: String) async throws {
            try lock.withLock {
                if let remaining = failingSets[key], remaining > 0 {
                    failingSets[key] = remaining - 1
                    throw KeychainError.unexpectedStatus(-34018)
                }
                log.append(value == nil ? "delete \(key)" : "set \(key)")
                storage[key] = value
            }
        }

        var writes: [String] { lock.withLock { log } }
        func failGets(_ key: String, times: Int) { lock.withLock { failingGets[key] = times } }
        func failSets(_ key: String, times: Int) { lock.withLock { failingSets[key] = times } }
        func clearWrites() { lock.withLock { log = [] } }
        func value(_ key: String) -> String? { lock.withLock { storage[key] } }
    }

    private final class SuspendedSender: @unchecked Sendable {
        private var continuation: CheckedContinuation<Int, Error>?
        private(set) var calls = 0

        var sender: WebhookDestinationModel.TestSender {
            { _, _ in
                try await withCheckedThrowingContinuation { continuation in
                    Task { @MainActor in
                        self.calls += 1
                        self.continuation = continuation
                    }
                }
            }
        }

        func finish(_ status: Int) {
            continuation?.resume(returning: status)
            continuation = nil
        }
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "WebhookConsentReviewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeContainer(
        secrets: any SecretsStore = InMemorySecretsStore(),
        defaults: UserDefaults? = nil
    ) -> AppContainer {
        let defaults = defaults ?? ephemeralDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        preferences.enabledCategoryIds = ["steps"]
        let healthStore = HealthStoreClient()
        return AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: try! HistoryStore.inMemory(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            consentStore: HealthExportConsentStore(defaults: defaults),
            automaticWorkoutConsentStore: AutomaticWorkoutConsentStore(defaults: defaults),
            orchestratorFactory: AppContainer.defaultOrchestratorFactory(runGate: ExportRunGate(), healthStore: healthStore)
        )
    }

    private func makeModel(
        _ container: AppContainer,
        sendTest: @escaping WebhookDestinationModel.TestSender = { _, _ in 200 }
    ) async -> WebhookDestinationModel {
        let model = WebhookDestinationModel(sendTest: sendTest)
        model.attach(container)
        await model.load()
        return model
    }

    private func enrol(_ container: AppContainer, endpoint: String? = nil, token: String? = nil) async throws {
        try await container.saveWebhookSettings(endpoint: endpoint ?? urlA, token: token ?? tokenA, tokenHeader: "Authorization")
        let maybeScope = await container.currentConsentScope(for: .webhook)
        let scope = try XCTUnwrap(maybeScope)
        let accepted = await container.acceptConsentIfCurrent(scope)
        XCTAssertTrue(accepted)
    }

    private func configuredIDs(_ container: AppContainer) async -> Set<String> {
        await IntentRunner.configuredSinkIds(container)
    }

    func test_item1_savingAWebhookDoesNotEnrolItUntilConsentIsAccepted() async throws {
        let container = makeContainer()
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")

        var ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
        var orchestrator = await container.orchestratorFactory()
        var sinkIDs = await orchestrator.configuredSinkIds
        XCTAssertFalse(sinkIDs.contains("webhook"))

        let maybeScope = await container.currentConsentScope(for: .webhook)
        let scope = try XCTUnwrap(maybeScope)
        let accepted = await container.acceptConsentIfCurrent(scope)
        XCTAssertTrue(accepted)

        ids = await configuredIDs(container)
        XCTAssertTrue(ids.contains("webhook"))
        orchestrator = await container.orchestratorFactory()
        sinkIDs = await orchestrator.configuredSinkIds
        XCTAssertTrue(sinkIDs.contains("webhook"))
        let ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)
    }

    func test_item1_sendTestSendsWithoutSavingOrEnrolling() async throws {
        let container = makeContainer()
        var sent: [URL] = []
        let model = await makeModel(container, sendTest: { configuration, _ in
            await MainActor.run { sent.append(configuration.endpoint) }
            return 200
        })
        model.endpoint = urlA
        model.token = tokenA

        await model.sendTest()

        XCTAssertEqual(sent, [URL(string: urlA)!])
        XCTAssertEqual(model.testStatus, .delivered(host: "hooks.example.com", statusCode: 200))
        let stored = try await container.loadWebhookSettings()
        XCTAssertNil(stored)
        let ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
    }

    func test_item1_leavingOrDecliningKeepsTheWebhookOutOfExports() async throws {
        let container = makeContainer()
        let model = await makeModel(container)
        model.endpoint = urlA
        model.token = tokenA

        await model.continueToConsent()
        XCTAssertNotNil(model.presentedConsent)
        model.declineConsent()
        model.leave()
        await container.webhookWritesSettled()

        let stored = try await container.loadWebhookSettings()
        XCTAssertEqual(stored?.endpoint, urlA)
        let ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
        XCTAssertFalse(container.preferences.webhookExportEnabled)
    }

    func test_item1_allowingInTheScreenEnrolsTheWebhook() async throws {
        let container = makeContainer()
        let model = await makeModel(container)
        model.endpoint = urlA

        await model.continueToConsent()
        let scope = try XCTUnwrap(model.presentedConsent)
        await model.allowConsent(scope)

        XCTAssertNil(model.presentedConsent)
        XCTAssertEqual(model.consentStatus, .current)
        let ids = await configuredIDs(container)
        XCTAssertTrue(ids.contains("webhook"))
    }

    func test_item1_removingTheWebhookUnenrolsIt() async throws {
        let container = makeContainer()
        try await enrol(container)
        let model = await makeModel(container)

        await model.remove()
        model.endpoint = urlB
        model.leave()
        await container.webhookWritesSettled()

        let ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
    }

    func test_item2_resetWhileTheScreenIsOpenWritesNothingBack() async throws {
        let secrets = InMemorySecretsStore()
        let container = makeContainer(secrets: secrets)
        try await enrol(container)
        let model = await makeModel(container)
        XCTAssertEqual(model.endpoint, urlA)

        container.prepareForReset()
        for key in AppContainer.resettableSecretKeys { try await secrets.set(nil, for: key) }
        container.preferences.reset()
        container.consentStore.reset()

        model.leave()
        await container.webhookWritesSettled()

        let stored = try await container.loadWebhookSettings()
        XCTAssertNil(stored)
        let ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))

        await model.load()
        XCTAssertEqual(model.endpoint, "")
        XCTAssertEqual(model.token, "")
    }

    func test_item1_reopeningRightAfterBackLoadsTheQueuedWrite() async throws {
        let container = makeContainer()
        try await enrol(container)
        let first = await makeModel(container)
        first.endpoint = urlB
        first.token = tokenB
        first.leave()

        let second = await makeModel(container)
        XCTAssertEqual(second.endpoint, urlB)
        XCTAssertEqual(second.token, tokenB)
        second.leave()
        await container.webhookWritesSettled()

        let stored = try await container.loadWebhookSettings()
        XCTAssertEqual(stored?.endpoint, urlB)
    }

    func test_item1_removeThenQuickBackDoesNotWriteTheOldDraft() async throws {
        let container = makeContainer()
        try await enrol(container)
        let model = await makeModel(container)
        model.endpoint = urlB

        let removal = Task { await model.remove() }
        await Task.yield()
        XCTAssertEqual(model.endpoint, "")
        model.leave()
        await removal.value
        await container.webhookWritesSettled()

        let stored = try await container.loadWebhookSettings()
        XCTAssertNil(stored)
    }

    func test_item2_resetAfterAQueuedLeaveWriteStoresNothing() async throws {
        let container = makeContainer()
        let model = await makeModel(container)
        model.endpoint = urlA
        model.token = tokenA

        model.leave()
        container.prepareForReset()
        await container.webhookWritesSettled()

        let stored = try await container.loadWebhookSettings()
        XCTAssertNil(stored)
    }

    func test_upgradeEnrolsAStoredWebhookWhoseConsentIsCurrent() async throws {
        let defaults = ephemeralDefaults()
        let container = makeContainer(defaults: defaults)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")
        let maybeScope = await container.webhookConsentScope()
        container.consentStore.accept(try XCTUnwrap(maybeScope))
        defaults.removeObject(forKey: PreferencesStore.Key.webhookExportEnabled)

        await container.migrateWebhookEnrolmentIfNeeded()

        XCTAssertTrue(container.preferences.webhookExportEnabled)
        let ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)
    }

    func test_upgradeLeavesAWebhookWithoutCurrentConsentOff() async throws {
        let defaults = ephemeralDefaults()
        let container = makeContainer(defaults: defaults)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")
        container.consentStore.accept(HealthExportConsentScope(
            destination: .webhook(scheme: "https", host: "hooks.example.com", port: nil, pathSHA256: "legacy"),
            enabledCategoryIds: ["steps"]
        ))
        defaults.removeObject(forKey: PreferencesStore.Key.webhookExportEnabled)

        await container.migrateWebhookEnrolmentIfNeeded()

        XCTAssertFalse(container.preferences.webhookExportEnabled)
        XCTAssertNotNil(defaults.object(forKey: PreferencesStore.Key.webhookExportEnabled))
        let ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
    }

    func test_upgradeMigrationRunsBeforeExportsReadEnrolment() async throws {
        let defaults = ephemeralDefaults()
        let container = makeContainer(defaults: defaults)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")
        let maybeScope = await container.webhookConsentScope()
        container.consentStore.accept(try XCTUnwrap(maybeScope))
        defaults.removeObject(forKey: PreferencesStore.Key.webhookExportEnabled)

        let ids = await configuredIDs(container)
        XCTAssertTrue(ids.contains("webhook"))
    }

    func test_upgradeMigrationWritesNothingWhenKeychainReadFails() async throws {
        let defaults = ephemeralDefaults()
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets, defaults: defaults)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")
        defaults.removeObject(forKey: PreferencesStore.Key.webhookExportEnabled)
        secrets.failGets(WebhookSecretKeys.endpoint, times: 1)

        await container.migrateWebhookEnrolmentIfNeeded()

        XCTAssertNil(defaults.object(forKey: PreferencesStore.Key.webhookExportEnabled))
    }

    func test_item8_unreadablePreviousSettingsAbortTheSaveBeforeWriting() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        try await enrol(container)
        secrets.clearWrites()
        secrets.failGets(WebhookSecretKeys.token, times: 1)

        do {
            try await container.saveWebhookSettings(endpoint: urlB, token: tokenB, tokenHeader: "Authorization")
            XCTFail("expected a read error")
        } catch {}

        XCTAssertEqual(secrets.writes, [])
        XCTAssertEqual(secrets.value(WebhookSecretKeys.endpoint), urlA)
    }

    func test_item3_editedURLNeverShowsTheOldURLsConsentAsCurrent() async throws {
        let container = makeContainer()
        try await enrol(container)
        let model = await makeModel(container)
        XCTAssertEqual(model.consentStatus, .current)

        model.endpoint = urlB
        await model.sendTest()

        XCTAssertEqual(model.consentStatus, .reviewRequired)
        await model.reviewConsent()
        let presented = try XCTUnwrap(model.presentedConsent)
        XCTAssertEqual(presented.destination.displayName, "other.example.com")
    }

    func test_item4_editingDuringATestReturnsTheTestCardToIdle() async throws {
        let container = makeContainer()
        let sender = SuspendedSender()
        let model = await makeModel(container, sendTest: sender.sender)
        model.endpoint = urlA

        let running = Task { await model.sendTest() }
        for _ in 0..<1_000 where sender.calls == 0 { await Task.yield() }
        XCTAssertEqual(sender.calls, 1)
        XCTAssertEqual(model.testStatus, .sending)

        model.token = tokenB
        XCTAssertEqual(model.testStatus, .idle)
        XCTAssertTrue(model.canSendTest)

        sender.finish(200)
        await running.value
        XCTAssertEqual(model.testStatus, .idle)
        XCTAssertTrue(model.canSendTest)
    }

    func test_item5_changingTheEndpointAndBackDoesNotRestoreConsent() async throws {
        let container = makeContainer()
        try await enrol(container)
        try await container.saveWebhookSettings(endpoint: urlB, token: tokenA, tokenHeader: "Authorization")
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")

        let ready = await container.webhookExportIsReady()
        XCTAssertFalse(ready)
    }

    func test_item5_queryOnlyChangeRequiresNewConsent() async throws {
        let container = makeContainer()
        try await enrol(container, endpoint: "https://hooks.example.com/p?chat_id=1")
        try await container.saveWebhookSettings(endpoint: "https://hooks.example.com/p?chat_id=2", token: tokenA, tokenHeader: "Authorization")

        let ready = await container.webhookExportIsReady()
        XCTAssertFalse(ready)
    }

    func test_item5_tokenRotationKeepsConsent() async throws {
        let container = makeContainer()
        try await enrol(container)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenB, tokenHeader: "X-Token")

        let ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)
    }

    func test_item6_keychainReadFailureShowsAnErrorAndLeavingWritesNothing() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        try await enrol(container)
        secrets.failGets(WebhookSecretKeys.endpoint, times: 1)
        secrets.clearWrites()

        let model = await makeModel(container)
        XCTAssertNotNil(model.loadError)
        model.leave()
        await container.webhookWritesSettled()

        let writes = secrets.writes
        XCTAssertEqual(writes, [])
        let stored = try await container.loadWebhookSettings()
        XCTAssertEqual(stored?.endpoint, urlA)
        let ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)

        await model.load()
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.endpoint, urlA)
    }

    func test_item6_loadWebhookSettingsThrowsOnReadFailure() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")
        secrets.failGets(WebhookSecretKeys.token, times: 1)

        do {
            _ = try await container.loadWebhookSettings()
            XCTFail("expected a read error")
        } catch {}
    }

    func test_item7_invalidURLEditPausesUntilTheNextValidSave() async throws {
        let container = makeContainer()
        try await enrol(container)

        let model = await makeModel(container)
        model.endpoint = "http://hooks.example.com/a"
        model.leave()
        await container.webhookWritesSettled()

        var ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
        let stored = try await container.loadWebhookSettings()
        XCTAssertEqual(stored?.endpoint, urlA)

        model.endpoint = urlA
        model.leave()
        await container.webhookWritesSettled()

        ids = await configuredIDs(container)
        XCTAssertTrue(ids.contains("webhook"))
        let ready = await container.webhookExportIsReady()
        XCTAssertTrue(ready)
    }

    func test_item7_invalidTokenWithUnchangedURLIsNotSilentlyDropped() async throws {
        let container = makeContainer()
        try await enrol(container)

        let model = await makeModel(container)
        model.token = "Bearer abc123"
        XCTAssertEqual(model.tokenValidationMessage, WebhookConfigurationError.invalidToken.localizedDescription)
        XCTAssertNil(model.endpointValidationMessage)
        model.leave()
        await container.webhookWritesSettled()

        let ids = await configuredIDs(container)
        XCTAssertFalse(ids.contains("webhook"))
        let stored = try await container.loadWebhookSettings()
        XCTAssertEqual(stored?.token, tokenA)
    }

    func test_item8_failedTokenWriteNeverPairsTheNewURLWithTheOldToken() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        try await enrol(container)
        secrets.failSets(WebhookSecretKeys.token, times: 1)

        do {
            try await container.saveWebhookSettings(endpoint: urlB, token: tokenB, tokenHeader: "Authorization")
            XCTFail("expected a write error")
        } catch {}

        let endpoint = secrets.value(WebhookSecretKeys.endpoint)
        let token = secrets.value(WebhookSecretKeys.token)
        XCTAssertFalse(endpoint == urlB && token == tokenA)
        XCTAssertEqual(endpoint, urlA)
        XCTAssertEqual(token, tokenA)
    }

    func test_item8_failedRestoreLeavesNoEndpoint() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        try await enrol(container)
        secrets.failSets(WebhookSecretKeys.token, times: 2)

        do {
            try await container.saveWebhookSettings(endpoint: urlB, token: tokenB, tokenHeader: "Authorization")
            XCTFail("expected a write error")
        } catch {}

        let endpoint = secrets.value(WebhookSecretKeys.endpoint)
        let token = secrets.value(WebhookSecretKeys.token)
        XCTAssertFalse(endpoint == urlB && token == tokenA)
        XCTAssertFalse(endpoint == urlA && token == tokenB)
    }

    func test_item8_endpointChangeWritesTheEndpointLast() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        try await container.saveWebhookSettings(endpoint: urlA, token: tokenA, tokenHeader: "Authorization")
        secrets.clearWrites()

        try await container.saveWebhookSettings(endpoint: urlB, token: tokenB, tokenHeader: "X-Token")

        let writes = secrets.writes
        XCTAssertEqual(writes.first, "delete \(WebhookSecretKeys.endpoint)")
        XCTAssertEqual(writes.last, "set \(WebhookSecretKeys.endpoint)")
        XCTAssertEqual(writes.count, 4)
    }

    func test_item9_allConfiguredDestinationsSkipsUnconsentedDestinations() async throws {
        let container = makeContainer()
        container.preferences.githubOwner = "octocat"
        container.preferences.githubRepo = "health"
        container.preferences.githubBranch = "main"
        try await KeychainTokenVault(secrets: container.secrets).save(StoredTokens(
            accessToken: "gho_test",
            refreshToken: nil,
            accessExpiresAt: Date().addingTimeInterval(3600),
            refreshExpiresAt: Date().addingTimeInterval(3600)
        ))
        container.consentStore.accept(HealthExportConsentScope(
            destination: .github(owner: "octocat", repo: "health", branch: "main", subdir: ""),
            enabledCategoryIds: ["steps"]
        ))
        try await enrol(container)
        try await container.saveWebhookSettings(endpoint: urlB, token: tokenA, tokenHeader: "Authorization")

        let request = try await IntentRunner.request(
            mode: .lastDayOnly,
            sinkFilter: DestinationOption.allEnabled.sinkIds,
            consentedOnly: true,
            container: container
        )
        XCTAssertEqual(request.enabledSinkIds, ["github"])
    }

    func test_item9_allConfiguredWithNothingConsentedAsksForConsent() async throws {
        let container = makeContainer()
        try await enrol(container)
        container.preferences.enabledCategoryIds = ["steps", "sleep"]

        do {
            _ = try await IntentRunner.request(
                mode: .lastDayOnly,
                sinkFilter: DestinationOption.allEnabled.sinkIds,
                consentedOnly: true,
                container: container
            )
            XCTFail("expected consentRequired")
        } catch let error as IntentError {
            guard case .consentRequired = error else { return XCTFail("expected consentRequired, got \(error)") }
        }
    }

    func test_item10_webhookRevisionChangesOnlyAfterTheLeaveWriteCompletes() async throws {
        let secrets = ScriptedSecretsStore()
        let container = makeContainer(secrets: secrets)
        var observedEndpoints: [String?] = []
        let probe = container.$webhookRevision.dropFirst().sink { _ in
            observedEndpoints.append(secrets.value(WebhookSecretKeys.endpoint))
        }
        defer { probe.cancel() }
        let before = container.webhookRevision
        let model = await makeModel(container)
        model.endpoint = urlA

        model.leave()
        await container.webhookWritesSettled()

        XCTAssertGreaterThan(container.webhookRevision, before)
        XCTAssertEqual(observedEndpoints.last, urlA)
        XCTAssertFalse(observedEndpoints.contains(where: { $0 == nil }))
    }

    func test_item11_enrolledWebhookStaysConfiguredWithZeroCategories() async throws {
        let container = makeContainer()
        try await enrol(container)
        container.preferences.enabledCategoryIds = []

        let ids = await configuredIDs(container)
        XCTAssertTrue(ids.contains("webhook"))
        let configured = await container.webhookExportIsConfigured()
        XCTAssertTrue(configured)

        do {
            _ = try await IntentRunner.request(
                mode: .lastDayOnly,
                sinkFilter: DestinationOption.webhookOnly.sinkIds,
                container: container
            )
            XCTFail("expected noCategoriesEnabled")
        } catch let error as IntentError {
            guard case .noCategoriesEnabled = error else { return XCTFail("expected noCategoriesEnabled, got \(error)") }
        }
    }
}
