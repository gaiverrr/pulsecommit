import Foundation
import HealthCore
import os
import UIKit

private final class WeakAutomaticWorkoutContainer: @unchecked Sendable {
    weak var value: AppContainer?
    init(_ value: AppContainer) { self.value = value }
}

private let containerLogger = Logger(subsystem: "app.pulsecommit", category: "container")

/// Constructs a `HistoryStore` with two-tier graceful fallback:
/// 1. Try on-disk SwiftData container (normal path).
/// 2. On failure, fall back to in-memory — recoverable for the current launch.
/// 3. If that also fails (e.g. schema conflict so severe that even an
///    in-memory `ModelContainer` cannot be built), substitute a no-op store
///    and log a `.fault`. The app must launch even in this degraded state.
@MainActor
func makeHistoryStore(
    onDisk: () throws -> HistoryStore,
    inMemory: () throws -> HistoryStore,
    log: (String) -> Void
) -> HistoryStore {
    do {
        return try onDisk()
    } catch {
        log("HistoryStore on-disk init failed: \(error). Falling back to in-memory.")
    }
    do {
        return try inMemory()
    } catch {
        log("HistoryStore in-memory fallback also failed: \(error). Continuing with no-op store.")
        return HistoryStore.noOp()
    }
}

extension AppContainer {
    /// `@MainActor`-isolated so that first access from an off-main caller
    /// (notably App Intents executors, which run on background queues)
    /// cannot lazily initialise `SwiftData` / `UIDevice` off the main actor.
    /// All call sites (`PulseCommitApp.body`, `IntentRunner.run`) already
    /// hop to MainActor; isolating the storage makes that invariant
    /// enforceable by the compiler.
    @MainActor static let shared: AppContainer = {
        #if DEBUG
        if MarketingDemo.isRequested() {
            return MarketingDemo.makeContainer()
        }
        #endif
        return .makeDefault()
    }()

    @MainActor static func makeDefault() -> AppContainer {
        // First-launch keychain cleanup is dispatched OFF the main actor by
        // KeychainSecretsStore — it owns a Task.detached and gates every
        // get/set on its completion. Runs once per install (sentinel inside
        // FirstLaunchCleanup), then becomes a no-op.
        let secrets: any SecretsStore = KeychainSecretsStore(
            firstLaunchCleanup: { FirstLaunchCleanup.runIfNeeded() }
        )
        let preferences = PreferencesStore()
        let history: HistoryStore = makeHistoryStore(
            onDisk: { try HistoryStore.onDisk() },
            inMemory: { try HistoryStore.inMemory() },
            log: { containerLogger.fault("\($0, privacy: .public)") }
        )
        let healthStore = HealthStoreClient()
        let registry = DefaultRegistryFactory.make(store: healthStore)
        let consentStore = HealthExportConsentStore()
        let automaticConsentStore = AutomaticWorkoutConsentStore()
        let automaticAttempts = AutomaticWorkoutAttemptFileStore.applicationSupport()

        // One gate for the whole app: the factory builds a fresh Orchestrator
        // per run (sinks depend on current preferences), so run mutual
        // exclusion must be shared here — otherwise a Shortcuts automation
        // firing while the user taps the Home button double-delivers to the
        // same repo/chat and races the SwiftData cursor.
        let runGate = ExportRunGate()

        let factory = defaultOrchestratorFactory(runGate: runGate, healthStore: healthStore)

        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: history,
            healthStore: healthStore,
            registry: registry,
            consentStore: consentStore,
            automaticWorkoutConsentStore: automaticConsentStore,
            automaticWorkoutAttempts: automaticAttempts,
            orchestratorFactory: factory
        )
        let sender = AutomaticWorkoutTelegramSender(
            currentCredentials: { [weak container] in
                await container?.currentAutomaticWorkoutTelegramCredentials()
            }
        )
        let weakContainer = WeakAutomaticWorkoutContainer(container)
        let coordinator = AutomaticWorkoutDeliveryCoordinator(
            source: AutomaticWorkoutHealthSource(store: healthStore, historyProvider: healthStore),
            sender: sender,
            attempts: automaticAttempts,
            configuration: { [weak container] in
                await container?.currentAutomaticWorkoutConfiguration()
            },
            protectedDataAvailable: {
                await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
            },
            stateDidChange: {
                await MainActor.run { weakContainer.value?.noteAutomaticWorkoutStateChanged() }
            }
        )
        container.installAutomaticWorkoutCoordinator(coordinator)
        container.installAutomaticWorkoutObserverController(
            AutomaticWorkoutObserverController(
                store: healthStore,
                preferences: preferences,
                coordinator: coordinator
            )
        )
        return container
    }
    @MainActor static func defaultOrchestratorFactory(
        runGate: ExportRunGate,
        healthStore: HealthStoreClient
    ) -> @MainActor (AppContainer) async -> Orchestrator {
        return { container in
            let tz = TimeZone.current
            let deviceName = UIDevice.current.name
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"

            let pipeline = SnapshotPipeline(
                registry: DefaultRegistryFactory.make(store: container.healthStore, timezone: tz,
                    zoneConfiguration: container.preferences.heartRateZoneConfiguration),
                timezone: tz,
                deviceName: deviceName,
                appVersion: appVersion
            )
            let historyChecker = HealthHistoryCoverageChecker(
                provider: healthStore,
                timezone: tz
            )

            var sinks: [any Sink] = []
            var requirements: [String: ConsentRequirement] = [:]
            var githubProvider: DeviceFlowCredentialProvider?
            var telegramCredentials: TelegramCredentials?
            let githubEnabled = container.preferences.githubExportEnabled
            let githubOwner = container.preferences.githubOwner ?? ""
            let githubRepo = container.preferences.githubRepo ?? ""
            let githubBranch = container.preferences.githubBranch ?? ""
            let githubSubdir = container.preferences.githubSubdir ?? ""
            if githubEnabled,
               !githubOwner.isEmpty, !githubRepo.isEmpty, !githubBranch.isEmpty,
               let provider = container.githubCredentialProvider() {
                githubProvider = provider
                requirements["github"] = ConsentRequirement(
                    sinkID: "github",
                    destination: .github(
                        owner: githubOwner,
                        repo: githubRepo,
                        branch: githubBranch,
                        subdir: githubSubdir
                    )
                )
            }
            var capturedTelegramBot: String?
            if container.preferences.telegramExportEnabled,
               let bot = (try? await container.secrets.get("tg_bot_token")) ?? nil,
               let chat = (try? await container.secrets.get("tg_chat_id")) ?? nil,
               !bot.isEmpty, !chat.isEmpty {
                let verbosity = SummaryVerbosity(rawValue: container.preferences.telegramVerbosity) ?? .standard
                let messageThreadID = container.preferences.telegramThreadId
                let creds = TelegramCredentials(
                    botToken: bot,
                    chatID: chat,
                    verbosity: verbosity,
                    messageThreadID: messageThreadID
                )
                telegramCredentials = creds
                capturedTelegramBot = bot
                requirements["telegram"] = ConsentRequirement(
                    sinkID: "telegram",
                    destination: .telegram(chatID: chat, messageThreadID: messageThreadID)
                )
            }

            var webhookConfiguration: WebhookConfiguration?
            if let target = await container.readyWebhookTarget() {
                webhookConfiguration = target.configuration
                requirements[WebhookDestinationSink.sinkID] = target.requirement
            }

            let telegramBotAtFactory = capturedTelegramBot
            let verifier: Orchestrator.ConsentVerifier = { requirement, categoryIDs in
                let currentCategories = await MainActor.run { container.preferences.enabledCategoryIds }
                guard currentCategories == categoryIDs else { return false }

                switch requirement.destination {
                case .github(let owner, let repo, let branch, let subdir):
                    let current = await MainActor.run {
                        (
                            container.preferences.githubExportEnabled,
                            container.preferences.githubOwner ?? "",
                            container.preferences.githubRepo ?? "",
                            container.preferences.githubBranch ?? "",
                            container.preferences.githubSubdir ?? ""
                        )
                    }
                    guard current.0, current.1 == owner, current.2 == repo,
                          current.3 == branch, current.4 == subdir else { return false }
                case .telegram(let chatID, let messageThreadID):
                    let currentBot = (try? await container.secrets.get("tg_bot_token")) ?? nil
                    let currentChat = (try? await container.secrets.get("tg_chat_id")) ?? nil
                    let current = await MainActor.run {
                        (container.preferences.telegramExportEnabled, container.preferences.telegramThreadId)
                    }
                    guard current.0, current.1 == messageThreadID,
                          currentBot == telegramBotAtFactory, currentChat == chatID else { return false }
                case .webhook:
                    guard await container.webhookTargetMatches(requirement.destination) else { return false }
                }

                return container.consentStore.hasCurrentConsent(
                    for: requirement.scope(for: categoryIDs)
                )
            }

            let categoryIDsAtFactory = container.preferences.enabledCategoryIds
            if let githubProvider, let requirement = requirements["github"] {
                sinks.append(GitHubSink(
                    credentialProvider: githubProvider,
                    session: EphemeralAPISession.make(),
                    authorizePayload: { await verifier(requirement, categoryIDsAtFactory) }
                ))
            }
            if let telegramCredentials, let requirement = requirements["telegram"] {
                sinks.append(TelegramSink(
                    credentials: telegramCredentials,
                    session: EphemeralAPISession.make(),
                    authorizePayload: { await verifier(requirement, categoryIDsAtFactory) }
                ))
            }
            if let webhookConfiguration, let requirement = requirements[WebhookDestinationSink.sinkID] {
                sinks.append(WebhookDestinationSink(sink: WebhookSink(
                    configuration: webhookConfiguration,
                    session: EphemeralAPISession.make(),
                    authorizePayload: { await verifier(requirement, categoryIDsAtFactory) }
                )))
            }

            return Orchestrator(
                windowResolver: ExportWindowResolver(timezone: tz),
                pipeline: pipeline,
                sinks: sinks,
                historyStore: container.history,
                isProtectedDataAvailable: {
                    await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
                },
                runGate: runGate,
                consentRequirements: requirements,
                consentVerifier: verifier,
                historyValidator: { from, to, categoryIDs in
                    try await historyChecker.validate(
                        from: from,
                        to: to,
                        enabledCategoryIds: categoryIDs
                    )
                }
            )
        }
    }
}
