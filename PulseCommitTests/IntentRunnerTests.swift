import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class IntentRunnerTests: XCTestCase {
    func test_exportMode_todayMapsToLiveCurrentDay() {
        XCTAssertEqual(IntentRunner.exportMode(for: .today), .todayLive)
    }

    func test_exportMode_last1dKeepsYesterdaySemantics() {
        XCTAssertEqual(WindowOption.last1d.rawValue, "last1d")
        XCTAssertEqual(IntentRunner.exportMode(for: .last1d), .lastDayOnly)
    }

    func test_request_todayUsesEnabledCategoriesAndSelectedConfiguredSink() async throws {
        let container = try await makeContainer()
        container.preferences.enabledCategoryIds = ["steps", "sleep"]

        let request = try await IntentRunner.request(
            mode: .todayLive,
            sinkFilter: ["telegram"],
            container: container
        )

        XCTAssertEqual(request.mode, .todayLive)
        XCTAssertEqual(request.enabledCategoryIds, ["steps", "sleep"])
        XCTAssertEqual(request.enabledSinkIds, ["telegram"])
    }

    func test_allRoutedModesRejectMissingConsentWithActionableError() async throws {
        for mode in [ExportRequest.Mode.todayLive, .lastDayOnly, .lastNDays(1), .range(from: Date(timeIntervalSince1970: 1_700_000_000), to: Date(timeIntervalSince1970: 1_700_086_400))] {
            let container = try await makeContainer(consentAccepted: false)
            do {
                _ = try await IntentRunner.run(mode: mode, container: container)
                XCTFail("expected consentRequired")
            } catch let error as IntentError {
                guard case .consentRequired = error else {
                    return XCTFail("expected consentRequired, got \(error)")
                }
                XCTAssertEqual(
                    String(localized: error.localizedStringResource),
                    "Open Pulse Commit to review consent for this Health export destination."
                )
            }
        }
    }

    func test_destinationOption_rawValuesStayStable() {
        XCTAssertEqual(DestinationOption.both.rawValue, "both")
        XCTAssertEqual(DestinationOption.githubOnly.rawValue, "githubOnly")
        XCTAssertEqual(DestinationOption.telegramOnly.rawValue, "telegramOnly")
        XCTAssertEqual(DestinationOption.webhookOnly.rawValue, "webhookOnly")
        XCTAssertEqual(DestinationOption.allEnabled.rawValue, "allEnabled")
        for raw in ["both", "githubOnly", "telegramOnly", "webhookOnly", "allEnabled"] {
            XCTAssertEqual(DestinationOption(rawValue: raw)?.rawValue, raw)
        }
    }

    func test_destinationOption_both_neverIncludesWebhook() {
        XCTAssertEqual(DestinationOption.both.sinkIds, ["github", "telegram"])
    }

    func test_destinationOption_webhookOnly_mapsToWebhook() {
        XCTAssertEqual(DestinationOption.webhookOnly.sinkIds, ["webhook"])
    }

    func test_request_both_excludesConfiguredWebhook() async throws {
        let container = try await makeContainer(webhookConfigured: true)
        let request = try await IntentRunner.request(
            mode: .lastDayOnly,
            sinkFilter: DestinationOption.both.sinkIds,
            container: container
        )
        XCTAssertEqual(request.enabledSinkIds, ["github", "telegram"])
    }

    func test_request_webhookOnly_returnsWebhook() async throws {
        let container = try await makeContainer(webhookConfigured: true)
        let request = try await IntentRunner.request(
            mode: .lastDayOnly,
            sinkFilter: DestinationOption.webhookOnly.sinkIds,
            container: container
        )
        XCTAssertEqual(request.enabledSinkIds, ["webhook"])
    }

    func test_request_allEnabled_returnsEveryConfiguredDestination() async throws {
        let container = try await makeContainer(webhookConfigured: true)
        let request = try await IntentRunner.request(
            mode: .lastDayOnly,
            sinkFilter: DestinationOption.allEnabled.sinkIds,
            container: container
        )
        XCTAssertEqual(request.enabledSinkIds, ["github", "telegram", "webhook"])
    }

    func test_request_allEnabled_withoutWebhook_returnsConfiguredOnly() async throws {
        let container = try await makeContainer()
        let request = try await IntentRunner.request(
            mode: .lastDayOnly,
            sinkFilter: DestinationOption.allEnabled.sinkIds,
            container: container
        )
        XCTAssertEqual(request.enabledSinkIds, ["github", "telegram"])
    }

    func test_request_webhookOnly_unconfigured_throwsWebhookWording() async throws {
        let container = try await makeContainer()
        do {
            _ = try await IntentRunner.request(
                mode: .lastDayOnly,
                sinkFilter: DestinationOption.webhookOnly.sinkIds,
                container: container
            )
            XCTFail("expected webhookNotConfigured")
        } catch let error as IntentError {
            guard case .webhookNotConfigured = error else {
                return XCTFail("expected webhookNotConfigured, got \(error)")
            }
            XCTAssertEqual(
                String(localized: error.localizedStringResource),
                "Set up the Webhook destination in Pulse Commit first."
            )
        }
    }

    func test_request_both_onlyWebhookConfigured_pointsToWebhookOptions() async throws {
        let container = try await makeContainer(webhookConfigured: true)
        container.preferences.githubExportEnabled = false
        container.preferences.telegramExportEnabled = false
        for option in [DestinationOption.both, .githubOnly, .telegramOnly] {
            do {
                _ = try await IntentRunner.request(
                    mode: .lastDayOnly,
                    sinkFilter: option.sinkIds,
                    container: container
                )
                XCTFail("expected webhookNotSelected for \(option)")
            } catch let error as IntentError {
                guard case .webhookNotSelected = error else {
                    return XCTFail("expected webhookNotSelected, got \(error)")
                }
                XCTAssertEqual(
                    String(localized: error.localizedStringResource),
                    "Only the webhook is set up. Set Destinations to Webhook only or All configured destinations."
                )
            }
        }
    }

    func test_request_githubOnly_unconfigured_namesSelectedDestination() async throws {
        let container = try await makeContainer()
        container.preferences.githubExportEnabled = false
        let message = await requestErrorMessage(container: container, filter: .githubOnly)
        XCTAssertEqual(message, "The destination selected in Destinations is not set up. Connect it in Pulse Commit.")
    }

    func test_request_telegramOnly_githubAndWebhookConfigured_pointsToWebhookOptions() async throws {
        let container = try await makeContainer(webhookConfigured: true)
        container.preferences.telegramExportEnabled = false
        let message = await requestErrorMessage(container: container, filter: .telegramOnly)
        XCTAssertEqual(
            message,
            "The destination selected in Destinations is not set up. The webhook is used only with Webhook only or All configured destinations."
        )
    }

    func test_request_both_nothingConfigured_doesNotSuggestWebhook() async throws {
        let container = try await makeContainer()
        container.preferences.githubExportEnabled = false
        container.preferences.telegramExportEnabled = false
        let message = await requestErrorMessage(container: container, filter: .both)
        XCTAssertEqual(message, "No destinations configured. Connect GitHub or Telegram in Pulse Commit.")
    }

    private func requestErrorMessage(container: AppContainer, filter: DestinationOption) async -> String? {
        do {
            _ = try await IntentRunner.request(
                mode: .lastDayOnly,
                sinkFilter: filter.sinkIds,
                container: container
            )
            XCTFail("expected an IntentError for \(filter)")
            return nil
        } catch let error as IntentError {
            return String(localized: error.localizedStringResource)
        } catch {
            XCTFail("unexpected error \(error)")
            return nil
        }
    }

    func test_configuredSinkIds_bothConfiguredAndEnabled_returnsBoth() async throws {
        let container = try await makeContainer()
        let ids = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(ids, ["github", "telegram"])
    }

    func test_configuredSinkIds_telegramToggledOff_returnsGitHubOnly() async throws {
        let container = try await makeContainer()
        container.preferences.telegramExportEnabled = false
        let ids = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(ids, ["github"])
    }

    func test_configuredSinkIds_githubToggledOff_returnsTelegramOnly() async throws {
        let container = try await makeContainer()
        container.preferences.githubExportEnabled = false
        let ids = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(ids, ["telegram"])
    }

    func test_run_bothTogglesOff_throwsNoDestinationsConfigured() async throws {
        let container = try await makeContainer()
        container.preferences.githubExportEnabled = false
        container.preferences.telegramExportEnabled = false

        do {
            _ = try await IntentRunner.run(mode: .lastNDays(1), container: container)
            XCTFail("expected IntentError.noDestinationsConfigured")
        } catch let error as IntentError {
            guard case .noDestinationsConfigured = error else {
                return XCTFail("expected noDestinationsConfigured, got \(error)")
            }
        }
    }

    func test_run_limitedHistoryThrowsActionableTypedError() async throws {
        let container = try await makeContainer(historyValidator: { _, _, _ in
            throw HealthHistoryCoverageError.limitedHistory
        })

        do {
            _ = try await IntentRunner.run(mode: .lastDayOnly, container: container)
            XCTFail("expected limitedHealthHistory")
        } catch let error as IntentError {
            guard case .limitedHealthHistory(let reason) = error else {
                return XCTFail("expected limitedHealthHistory, got \(error)")
            }
            let message = String(localized: error.localizedStringResource)
            XCTAssertEqual(reason, HealthHistoryCoverageError.limitedHistory.userMessage)
            XCTAssertTrue(message.contains("range"))
            XCTAssertTrue(message.contains("Full History"))
            XCTAssertTrue(message.contains("disable affected optional categories"))
        }
    }

    func test_configuredSinkIds_matchesFactoryBuiltSinks_whenOneToggleOff() async throws {
        let container = try await makeContainer()
        container.preferences.telegramExportEnabled = false

        let intentIds = await IntentRunner.configuredSinkIds(container)
        let orchestrator = await container.orchestratorFactory()
        let factoryIds = Set(await orchestrator.configuredSinkIds)
        XCTAssertEqual(intentIds, factoryIds)
    }

    /// Container with BOTH destinations fully configured (GitHub coords +
    /// stored tokens, Telegram bot + chat) and a factory that mirrors the
    /// production toggle-respecting sink construction.
    private func makeContainer(
        consentAccepted: Bool = true,
        webhookConfigured: Bool = false,
        historyValidator: @escaping Orchestrator.HistoryValidator = { _, _, _ in }
    ) async throws -> AppContainer {
        let secrets = InMemorySecretsStore()
        try await secrets.set("bot", for: "tg_bot_token")
        try await secrets.set("chat", for: "tg_chat_id")
        try await KeychainTokenVault(secrets: secrets).save(StoredTokens(
            accessToken: "gho_test",
            refreshToken: nil,
            accessExpiresAt: Date().addingTimeInterval(3600),
            refreshExpiresAt: Date().addingTimeInterval(3600)
        ))

        let preferences = PreferencesStore(defaults: ephemeralDefaults())
        preferences.githubOwner = "octocat"
        preferences.githubRepo = "hello"
        preferences.githubBranch = "main"

        let history = try HistoryStore.inMemory()
        let healthStore = HealthStoreClient()
        let registry = DefaultRegistryFactory.make(store: healthStore)
        let consentStore = HealthExportConsentStore(defaults: ephemeralDefaults())
        let githubScope = HealthExportConsentScope(
            destination: .github(owner: "octocat", repo: "hello", branch: "main", subdir: ""),
            enabledCategoryIds: preferences.enabledCategoryIds
        )
        let telegramScope = HealthExportConsentScope(
            destination: .telegram(chatID: "chat", messageThreadID: nil),
            enabledCategoryIds: preferences.enabledCategoryIds
        )
        if consentAccepted {
            consentStore.accept(githubScope)
            consentStore.accept(telegramScope)
        }

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
                let provider = DeviceFlowCredentialProvider(
                    vault: KeychainTokenVault(secrets: container.secrets),
                    client: GitHubDeviceFlowClient(session: .shared, clientID: GitHubAppConfig.clientID),
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
                sinks.append(TelegramSink(credentials: .init(botToken: bot, chatID: chat, verbosity: .standard), session: .shared))
            }
            return Orchestrator(
                windowResolver: ExportWindowResolver(timezone: tz),
                pipeline: pipeline,
                sinks: sinks,
                historyStore: container.history,
                consentRequirements: [
                    "github": ConsentRequirement(sinkID: "github", destination: githubScope.destination),
                    "telegram": ConsentRequirement(sinkID: "telegram", destination: telegramScope.destination)
                ],
                consentVerifier: { requirement, categories in
                    consentStore.hasCurrentConsent(for: requirement.scope(for: categories))
                },
                historyValidator: historyValidator
            )
        }

        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: history,
            healthStore: healthStore,
            registry: registry,
            consentStore: consentStore,
            orchestratorFactory: factory
        )
        if webhookConfigured {
            _ = try await container.saveWebhookSettings(
                endpoint: "https://hooks.example.com/pulse",
                token: "secret-token-value",
                tokenHeader: "Authorization"
            )
            container.preferences.webhookExportEnabled = true
        }
        return container
    }

    private func ephemeralDefaults() -> UserDefaults {
        let suiteName = "IntentRunnerTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}
