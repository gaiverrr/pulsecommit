import XCTest
import HealthCore
import HealthKit
@testable import PulseCommit

private actor DelayedTelegramSecrets: SecretsStore {
    private var values: [String: String] = [:]
    private var waiting: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var isWaiting = false

    func get(_ key: String) throws -> String? { values[key] }

    func set(_ value: String?, for key: String) async throws {
        if key == "tg_bot_token", value == "token-B" {
            isWaiting = true
            waiting?.resume()
            waiting = nil
            await withCheckedContinuation { release = $0 }
        }
        values[key] = value
    }

    func waitForDelayedWrite() async {
        if !isWaiting { await withCheckedContinuation { waiting = $0 } }
    }

    func releaseWrite() { release?.resume(); release = nil }
}

private actor RevisionWorkoutSource: AutomaticWorkoutQuerying {
    let candidate: AutomaticWorkoutCandidate
    init(candidate: AutomaticWorkoutCandidate) { self.candidate = candidate }
    func workouts(from: Date, to: Date) async throws -> [AutomaticWorkoutCandidate] { [candidate] }
}

private actor RevisionWorkoutSender: AutomaticWorkoutSending {
    func send(
        _ candidate: AutomaticWorkoutCandidate,
        scopeID: String,
        timeZoneIdentifier: String
    ) async -> AutomaticWorkoutSendResult {
        .delivered(messageID: 1)
    }
}

private final class RevisionObserverHealthStore: AutomaticWorkoutObserverHealthStore, @unchecked Sendable {
    func execute(_ query: HKQuery) {}
    func stop(_ query: HKQuery) {}
    func enableWorkoutBackgroundDelivery(completion: @escaping @Sendable (Bool, Error?) -> Void) {
        completion(true, nil)
    }
    func disableWorkoutBackgroundDelivery(completion: @escaping @Sendable (Bool, Error?) -> Void) {
        completion(true, nil)
    }
}

private actor SuspendingTelegramReadSecrets: SecretsStore {
    private var values: [String: String] = [:]
    private var suspendNextBotRead = false
    private var suspended = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var release: CheckedContinuation<Void, Never>?

    func get(_ key: String) async throws -> String? {
        let captured = values[key]
        if key == "tg_bot_token", suspendNextBotRead {
            suspendNextBotRead = false
            suspended = true
            waiters.forEach { $0.resume() }
            waiters.removeAll()
            await withCheckedContinuation { release = $0 }
        }
        return captured
    }

    func set(_ value: String?, for key: String) async throws { values[key] = value }
    func suspendNextRead() { suspendNextBotRead = true; suspended = false }
    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func resumeRead() { release?.resume(); release = nil }
}

@MainActor
final class AppContainerTests: XCTestCase {
    func test_automaticWorkoutStateRevisionTracksInvalidationAndAttemptChanges() async {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        let container = makeContainer(secrets: InMemorySecretsStore(), preferences: preferences)
        let observer = AutomaticWorkoutObserverController(
            store: RevisionObserverHealthStore(),
            preferences: preferences,
            reconcileAction: {}
        )
        container.installAutomaticWorkoutObserverController(observer)
        let initial = container.automaticWorkoutStateRevision

        preferences.telegramThreadId = 42
        for _ in 0..<4 { await Task.yield() }
        XCTAssertGreaterThan(container.automaticWorkoutStateRevision, initial)

        let afterInvalidation = container.automaticWorkoutStateRevision
        preferences.automaticWorkoutRegistrationFailed = true
        for _ in 0..<4 { await Task.yield() }
        XCTAssertGreaterThan(container.automaticWorkoutStateRevision, afterInvalidation)

        let afterRegistrationFailure = container.automaticWorkoutStateRevision
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let candidate = AutomaticWorkoutCandidate(
            id: UUID(),
            workout: WorkoutDTO(
                id: UUID().uuidString,
                type: .outdoorRun,
                startDate: now.addingTimeInterval(-600),
                endDate: now.addingTimeInterval(-10),
                durationMinutes: 10,
                distanceKm: 2,
                activeEnergyKcal: 100,
                avgHeartRate: 140,
                maxHeartRate: 160,
                route: [],
                durationSeconds: 600,
                distanceMeters: 2_000
            )
        )
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: RevisionWorkoutSource(candidate: candidate),
            sender: RevisionWorkoutSender(),
            attempts: container.automaticWorkoutAttempts,
            configuration: {
                AutomaticWorkoutDeliveryConfiguration(
                    scopeID: "scope", activationDate: now.addingTimeInterval(-500), timeZoneIdentifier: "UTC"
                )
            },
            protectedDataAvailable: { true },
            clock: { now },
            stateDidChange: { [weak container] in
                await MainActor.run { container?.noteAutomaticWorkoutStateChanged() }
            }
        )
        await coordinator.reconcile()

        XCTAssertGreaterThan(container.automaticWorkoutStateRevision, afterRegistrationFailure)
    }

    func test_lifecycleKeepsAutomaticOptInWithoutAnyPurchase() async {
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.automaticWorkoutTelegramEnabled = true
        let container = makeContainer(secrets: InMemorySecretsStore(), preferences: preferences)

        await container.handleAutomaticWorkoutLifecycleEvent()

        XCTAssertTrue(preferences.automaticWorkoutTelegramEnabled)
    }

    func test_automaticWorkoutSetupIsAvailableToEveryone() async throws {
        let secrets = InMemorySecretsStore()
        try await secrets.set("token-A", for: "tg_bot_token")
        try await secrets.set("chat-A", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.enabledCategoryIds = ["workouts"]
        let container = makeContainer(secrets: secrets, preferences: preferences)

        let resolvedScope = await container.automaticWorkoutDraftScope()
        let scope = try XCTUnwrap(resolvedScope)
        let didEnable = await container.enableAutomaticWorkoutDelivery(ifCurrent: scope)
        let configuration = await container.currentAutomaticWorkoutConfiguration()
        XCTAssertTrue(didEnable)
        XCTAssertNotNil(configuration)
    }

    func test_automaticWorkoutDraftRejectsABASecretChangeDuringSuspendedRead() async throws {
        let secrets = SuspendingTelegramReadSecrets()
        try await secrets.set("token-A", for: "tg_bot_token")
        try await secrets.set("chat-A", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.enabledCategoryIds = ["workouts"]
        let container = makeContainer(
            secrets: secrets,
            preferences: preferences
        )

        await secrets.suspendNextRead()
        let draft = Task { await container.automaticWorkoutDraftScope() }
        await secrets.waitUntilSuspended()
        await container.updateTelegramSecret("token-B", for: "tg_bot_token").value
        await container.updateTelegramSecret("token-A", for: "tg_bot_token").value
        await secrets.resumeRead()

        let result = await draft.value
        XCTAssertNil(result)
    }

    func test_automaticWorkoutEnableRejectsCategoryABAWhileSecretsSuspend() async throws {
        let secrets = SuspendingTelegramReadSecrets()
        try await secrets.set("token-A", for: "tg_bot_token")
        try await secrets.set("chat-A", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.enabledCategoryIds = ["workouts"]
        let container = makeContainer(
            secrets: secrets,
            preferences: preferences
        )
        let resolvedScope = await container.automaticWorkoutDraftScope()
        let scope = try XCTUnwrap(resolvedScope)

        await secrets.suspendNextRead()
        let enabling = Task { await container.enableAutomaticWorkoutDelivery(ifCurrent: scope) }
        await secrets.waitUntilSuspended()
        preferences.enabledCategoryIds = ["steps"]
        preferences.enabledCategoryIds = ["workouts"]
        await secrets.resumeRead()

        let enabled = await enabling.value
        XCTAssertFalse(enabled)
        XCTAssertFalse(preferences.automaticWorkoutTelegramEnabled)
        XCTAssertNil(container.automaticWorkoutConsentStore.record())
    }

    func test_automaticWorkoutCredentialReadRejectsMasterDisableDuringSuspension() async throws {
        let secrets = SuspendingTelegramReadSecrets()
        try await secrets.set("token-A", for: "tg_bot_token")
        try await secrets.set("chat-A", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.enabledCategoryIds = ["workouts"]
        let container = makeContainer(
            secrets: secrets,
            preferences: preferences
        )
        let resolvedScope = await container.automaticWorkoutDraftScope()
        let scope = try XCTUnwrap(resolvedScope)
        let enabled = await container.enableAutomaticWorkoutDelivery(ifCurrent: scope)
        XCTAssertTrue(enabled)

        await secrets.suspendNextRead()
        let credentials = Task { await container.currentAutomaticWorkoutTelegramCredentials() }
        await secrets.waitUntilSuspended()
        preferences.telegramExportEnabled = false
        preferences.telegramExportEnabled = true
        await secrets.resumeRead()

        let result = await credentials.value
        XCTAssertNil(result)
        XCTAssertFalse(preferences.automaticWorkoutTelegramEnabled)
        XCTAssertNil(container.automaticWorkoutConsentStore.record())
    }

    func test_telegramRapidEditsCannotAcceptOldTokenWhileKeychainWriteIsDelayed() async throws {
        let secrets = DelayedTelegramSecrets()
        try await secrets.set("token-A", for: "tg_bot_token")
        try await secrets.set("-1001234567890", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.enabledCategoryIds = ["steps"]
        let container = makeContainer(secrets: secrets, preferences: preferences)
        let originalScope = await container.currentConsentScope(for: .telegram)
        let original = try XCTUnwrap(originalScope)
        let firstAcceptance = await container.acceptConsentIfCurrent(original)
        XCTAssertTrue(firstAcceptance)

        let editB = container.updateTelegramSecret("token-B", for: "tg_bot_token")
        await secrets.waitForDelayedWrite()
        let duringEdit = await container.acceptConsentIfCurrent(original)
        XCTAssertFalse(duringEdit)
        let editC = container.updateTelegramSecret("token-C", for: "tg_bot_token")
        await secrets.releaseWrite()
        await editB.value
        await editC.value

        let stored = try await secrets.get("tg_bot_token")
        XCTAssertEqual(stored, "token-C")
        let matchesAfterWriting = await container.telegramCredentialsMatch(botToken: "token-C", chatID: "-1001234567890")
        XCTAssertTrue(matchesAfterWriting)
        let staleTokenMatches = await container.telegramCredentialsMatch(botToken: "token-A", chatID: "-1001234567890")
        XCTAssertFalse(staleTokenMatches)
        XCTAssertFalse(container.consentStore.hasCurrentConsent(for: original))
        let afterEdit = await container.acceptConsentIfCurrent(original)
        XCTAssertTrue(afterEdit)
    }
    func test_makeDefault_returnsNonNilContainer() {
        let container = AppContainer.makeDefault()
        XCTAssertNotNil(container.secrets)
        XCTAssertNotNil(container.preferences)
        XCTAssertNotNil(container.history)
        XCTAssertNotNil(container.healthStore)
        XCTAssertFalse(container.registry.all.isEmpty)
    }

    /// Compile-time + runtime guard: `AppContainer.shared` and `makeDefault()`
    /// are `@MainActor`-isolated, so accessing them from a non-main context
    /// must fail to compile. Inside this `@MainActor` test we should reach
    /// them directly without `await` and observe a stable identity.
    func test_shared_isMainActorAndStableIdentity() {
        let a = AppContainer.shared
        let b = AppContainer.shared
        XCTAssertTrue(a === b)
    }

    func test_orchestratorFactory_withNoSecrets_yieldsOrchestratorWithEmptySinks() async throws {
        let secrets = InMemorySecretsStore()
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIds, [])
    }

    func test_orchestratorFactory_withGitHubCoords_addsGitHubSink() async throws {
        let secrets = InMemorySecretsStore()
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        preferences.githubBranch = "main"
        preferences.githubSubdir = ""

        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIds, ["github"])
    }

    func test_orchestratorFactory_withGitHubAndTelegram_addsBothSinks() async throws {
        let secrets = InMemorySecretsStore()
        try await secrets.set("bot", for: "tg_bot_token")
        try await secrets.set("chat", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        preferences.githubBranch = "main"

        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(Set(sinkIds), Set(["github", "telegram"]))
    }

    func test_orchestratorFactory_whenGitHubExportDisabled_skipsGitHubSink() async throws {
        let secrets = InMemorySecretsStore()
        try await secrets.set("bot", for: "tg_bot_token")
        try await secrets.set("chat", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        preferences.githubBranch = "main"
        preferences.githubExportEnabled = false

        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIds, ["telegram"])
    }

    func test_orchestratorFactory_whenTelegramExportDisabled_skipsTelegramSink() async throws {
        let secrets = InMemorySecretsStore()
        try await secrets.set("bot", for: "tg_bot_token")
        try await secrets.set("chat", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        preferences.githubBranch = "main"
        preferences.telegramExportEnabled = false

        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIds, ["github"])
    }

    func test_orchestratorFactory_whenBothDestinationsDisabled_yieldsEmptySinks() async throws {
        let secrets = InMemorySecretsStore()
        try await secrets.set("bot", for: "tg_bot_token")
        try await secrets.set("chat", for: "tg_chat_id")
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        preferences.githubBranch = "main"
        preferences.githubExportEnabled = false
        preferences.telegramExportEnabled = false

        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIds, [])
    }

    func test_orchestratorFactory_withPartialGitHubCoords_skipsGitHubSink() async throws {
        let secrets = InMemorySecretsStore()
        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        // branch missing
        let container = makeContainer(secrets: secrets, preferences: preferences)
        let orchestrator = await container.orchestratorFactory()
        let sinkIds = await orchestrator.configuredSinkIds
        XCTAssertEqual(sinkIds, [])
    }

    @MainActor
    private func makeContainer(
        secrets: any SecretsStore,
        preferences: PreferencesStore
    ) -> AppContainer {
        let history = try! HistoryStore.inMemory()
        let healthStore = HealthStoreClient()
        let registry = DefaultRegistryFactory.make(store: healthStore)

        let factory: @MainActor (AppContainer) async -> Orchestrator = { container in
            let tz = TimeZone(identifier: "UTC")!
            let pipeline = SnapshotPipeline(
                registry: container.registry,
                timezone: tz,
                deviceName: "Test",
                appVersion: "1.0.0"
            )
            var sinks: [any Sink] = []
            if container.preferences.githubExportEnabled,
               let owner = container.preferences.githubOwner,
               let repo = container.preferences.githubRepo,
               let branch = container.preferences.githubBranch,
               !owner.isEmpty, !repo.isEmpty, !branch.isEmpty {
                let vault = InMemoryTokenVault()
                let client = GitHubDeviceFlowClient(
                    session: .shared,
                    clientID: GitHubAppConfig.clientID
                )
                let provider = DeviceFlowCredentialProvider(
                    vault: vault,
                    client: client,
                    clock: { Date() },
                    owner: owner,
                    repo: repo,
                    branch: branch,
                    subdir: container.preferences.githubSubdir ?? ""
                )
                sinks.append(GitHubSink(credentialProvider: provider, session: .shared))
            }
            if container.preferences.telegramExportEnabled,
               let bot = (try? await container.secrets.get("tg_bot_token")) ?? nil,
               let chat = (try? await container.secrets.get("tg_chat_id")) ?? nil,
               !bot.isEmpty, !chat.isEmpty {
                let v = SummaryVerbosity(rawValue: container.preferences.telegramVerbosity) ?? .standard
                sinks.append(TelegramSink(credentials: .init(botToken: bot, chatID: chat, verbosity: v), session: .shared))
            }
            return Orchestrator(
                windowResolver: ExportWindowResolver(timezone: tz),
                pipeline: pipeline,
                sinks: sinks,
                historyStore: container.history
            )
        }

        return AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: history,
            healthStore: healthStore,
            registry: registry,
            orchestratorFactory: factory
        )
    }

    func test_makeHistoryStore_returnsOnDiskInstanceWhenAvailable() {
        var logged: [String] = []
        let store = makeHistoryStore(
            onDisk: { try HistoryStore.inMemory() },
            inMemory: { try HistoryStore.inMemory() },
            log: { logged.append($0) }
        )
        XCTAssertFalse(store.isNoOp)
        XCTAssertTrue(logged.isEmpty)
    }

    func test_makeHistoryStore_fallsBackToInMemoryWhenOnDiskFails() {
        var logged: [String] = []
        let store = makeHistoryStore(
            onDisk: { throw NSError(domain: "test", code: 1) },
            inMemory: { try HistoryStore.inMemory() },
            log: { logged.append($0) }
        )
        XCTAssertFalse(store.isNoOp)
        XCTAssertEqual(logged.count, 1)
        XCTAssertTrue(logged[0].contains("on-disk init failed"))
    }

    func test_makeHistoryStore_degradesToNoOpWhenBothPathsFail() throws {
        var logged: [String] = []
        let store = makeHistoryStore(
            onDisk: { throw NSError(domain: "test", code: 1) },
            inMemory: { throw NSError(domain: "test", code: 2) },
            log: { logged.append($0) }
        )
        XCTAssertTrue(store.isNoOp)
        XCTAssertEqual(logged.count, 2)
        XCTAssertTrue(logged[1].contains("no-op"))
        // No-op store accepts writes silently and reports empty on reads.
        try store.append(HistoryEntry(
            startedAt: Date(),
            finishedAt: Date(),
            status: .success,
            sinks: ["github"],
            daysCovered: ["2026-05-16"]
        ))
        XCTAssertEqual(try store.recentEntries(limit: 10), [])
        XCTAssertNil(try store.cursor())
        XCTAssertNil(try store.latestGitHubCommitEntry())
    }

    func test_summaryVerbosity_isStringRawRepresentable() {
        XCTAssertEqual(SummaryVerbosity(rawValue: "compact"), .compact)
        XCTAssertEqual(SummaryVerbosity(rawValue: "standard"), .standard)
        XCTAssertEqual(SummaryVerbosity(rawValue: "verbose"), .verbose)
        XCTAssertEqual(SummaryVerbosity.standard.rawValue, "standard")
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suiteName = "AppContainerTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
