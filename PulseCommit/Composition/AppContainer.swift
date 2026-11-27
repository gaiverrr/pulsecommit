import Foundation
import HealthCore
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let secrets: any SecretsStore
    let preferences: PreferencesStore
    let history: HistoryStore
    let healthStore: any HealthStoreAuthorizing
    let registry: CategoryRegistry
    let consentStore: HealthExportConsentStore
    let automaticWorkoutConsentStore: AutomaticWorkoutConsentStore
    let automaticWorkoutAttempts: any AutomaticWorkoutAttemptStoring
    private(set) var automaticWorkoutCoordinator: AutomaticWorkoutDeliveryCoordinator?
    private(set) var automaticWorkoutObserverController: AutomaticWorkoutObserverController?
    @Published private(set) var automaticWorkoutStateRevision: UInt64 = 0
    @Published private(set) var webhookRevision: UInt64 = 0
    @Published private(set) var resetGeneration: UInt64 = 0
    var lastWebhookWrite: Task<Void, Never>?
    private let factoryClosure: @MainActor (AppContainer) async -> Orchestrator

    private var cachedGithubProvider: DeviceFlowCredentialProvider?
    private var cachedGithubProviderKey: String?
    private var pendingTelegramSecretEdits = 0
    private var failedTelegramSecretKeys = Set<String>()
    private var lastTelegramSecretEdit: Task<Void, Never>?
    private var telegramSecretRevision: UInt64 = 0

    init(
        secrets: any SecretsStore,
        preferences: PreferencesStore,
        history: HistoryStore,
        healthStore: any HealthStoreAuthorizing,
        registry: CategoryRegistry,
        consentStore: HealthExportConsentStore = HealthExportConsentStore(),
        automaticWorkoutConsentStore: AutomaticWorkoutConsentStore = AutomaticWorkoutConsentStore(),
        automaticWorkoutAttempts: any AutomaticWorkoutAttemptStoring = InMemoryAutomaticWorkoutAttemptStore(),
        orchestratorFactory: @escaping @MainActor (AppContainer) async -> Orchestrator
    ) {
        self.secrets = secrets
        self.preferences = preferences
        self.history = history
        self.healthStore = healthStore
        self.registry = registry
        self.consentStore = consentStore
        self.automaticWorkoutConsentStore = automaticWorkoutConsentStore
        self.automaticWorkoutAttempts = automaticWorkoutAttempts
        preferences.bindConsentStore(consentStore)
        preferences.bindAutomaticWorkoutConsentStore(automaticWorkoutConsentStore)
        self.factoryClosure = orchestratorFactory
    }

    func orchestratorFactory() async -> Orchestrator {
        await factoryClosure(self)
    }

    func installAutomaticWorkoutCoordinator(_ coordinator: AutomaticWorkoutDeliveryCoordinator) {
        automaticWorkoutCoordinator = coordinator
    }

    func installAutomaticWorkoutObserverController(_ controller: AutomaticWorkoutObserverController) {
        automaticWorkoutObserverController = controller
        preferences.bindAutomaticWorkoutConfigurationChanged { [weak self, weak controller] in
            Task { @MainActor in
                self?.noteAutomaticWorkoutStateChanged()
                controller?.refreshRegistration()
            }
        }
    }

    func noteWebhookChanged() {
        webhookRevision &+= 1
    }

    func noteAutomaticWorkoutStateChanged() {
        automaticWorkoutStateRevision &+= 1
    }

    func githubCredentialProvider() -> DeviceFlowCredentialProvider? {
        guard let owner = preferences.githubOwner, !owner.isEmpty,
              let repo = preferences.githubRepo, !repo.isEmpty,
              let branch = preferences.githubBranch, !branch.isEmpty else {
            cachedGithubProvider = nil
            cachedGithubProviderKey = nil
            return nil
        }
        let subdir = preferences.githubSubdir ?? ""
        let key = "\(owner)/\(repo)/\(branch)/\(subdir)"
        if let cached = cachedGithubProvider, cachedGithubProviderKey == key {
            return cached
        }
        let vault = KeychainTokenVault(secrets: secrets)
        let client = GitHubDeviceFlowClient(clientID: GitHubAppConfig.clientID)
        let provider = DeviceFlowCredentialProvider(
            vault: vault,
            client: client,
            owner: owner,
            repo: repo,
            branch: branch,
            subdir: subdir
        )
        cachedGithubProvider = provider
        cachedGithubProviderKey = key
        return provider
    }

    func invalidateGithubCredentialProvider() {
        cachedGithubProvider = nil
        cachedGithubProviderKey = nil
    }

    func currentConsentScope(
        for destination: HealthExportDestinationKind,
        categoryIDs: Set<String>? = nil
    ) async -> HealthExportConsentScope? {
        let categories = categoryIDs ?? preferences.enabledCategoryIds
        guard !categories.isEmpty else { return nil }
        switch destination {
        case .github:
            guard preferences.githubExportEnabled,
                  let owner = preferences.githubOwner, !owner.isEmpty,
                  let repo = preferences.githubRepo, !repo.isEmpty,
                  let branch = preferences.githubBranch, !branch.isEmpty,
                  await KeychainTokenVault.hasStoredTokens(in: secrets) else { return nil }
            return HealthExportConsentScope(
                destination: .github(
                    owner: owner,
                    repo: repo,
                    branch: branch,
                    subdir: preferences.githubSubdir ?? ""
                ),
                enabledCategoryIds: categories
            )
        case .telegram:
            guard pendingTelegramSecretEdits == 0, failedTelegramSecretKeys.isEmpty else { return nil }
            guard preferences.telegramExportEnabled,
                  let bot = (try? await secrets.get("tg_bot_token")) ?? nil, !bot.isEmpty,
                  let chat = (try? await secrets.get("tg_chat_id")) ?? nil, !chat.isEmpty else { return nil }
            guard pendingTelegramSecretEdits == 0, failedTelegramSecretKeys.isEmpty else { return nil }
            return HealthExportConsentScope(
                destination: .telegram(chatID: chat, messageThreadID: preferences.telegramThreadId),
                enabledCategoryIds: categories
            )
        case .webhook:
            return await webhookConsentScope(categoryIDs: categories)
        }
    }

    func acceptConsentIfCurrent(_ scope: HealthExportConsentScope) async -> Bool {
        guard let current = await currentConsentScope(
            for: scope.destination.kind,
            categoryIDs: Set(scope.enabledCategoryIds)
        ), current == scope, preferences.enabledCategoryIds == Set(scope.enabledCategoryIds),
          (scope.destination.kind != .telegram || (pendingTelegramSecretEdits == 0 && failedTelegramSecretKeys.isEmpty)) else {
            return false
        }
        consentStore.accept(scope)
        if scope.destination.kind == .webhook {
            preferences.webhookExportEnabled = true
            preferences.webhookPausedByInvalidEdit = false
            noteWebhookChanged()
        }
        return true
    }

    @discardableResult
    func updateTelegramSecret(_ input: String?, for key: String) -> Task<Void, Never> {
        precondition(key == "tg_bot_token" || key == "tg_chat_id")
        consentStore.invalidate(.telegram)
        automaticWorkoutConsentStore.invalidate()
        preferences.automaticWorkoutTelegramEnabled = false
        telegramSecretRevision &+= 1
        pendingTelegramSecretEdits += 1
        let previous = lastTelegramSecretEdit
        let secrets = self.secrets
        let task = Task { @MainActor in
            await previous?.value
            do {
                try await secrets.set(input, for: key)
                failedTelegramSecretKeys.remove(key)
            } catch {
                failedTelegramSecretKeys.insert(key)
            }
            pendingTelegramSecretEdits -= 1
        }
        lastTelegramSecretEdit = task
        return task
    }

    /// Wait for the existing serialized Keychain writes before treating a
    /// successful setup test as a configured export target.
    func telegramCredentialsMatch(botToken: String, chatID: String) async -> Bool {
        await lastTelegramSecretEdit?.value
        guard pendingTelegramSecretEdits == 0, failedTelegramSecretKeys.isEmpty else { return false }
        let storedBot = (try? await secrets.get("tg_bot_token")) ?? nil
        let storedChat = (try? await secrets.get("tg_chat_id")) ?? nil
        return pendingTelegramSecretEdits == 0 && failedTelegramSecretKeys.isEmpty &&
            storedBot == botToken && storedChat == chatID
    }

    func automaticWorkoutDraftScope() async -> AutomaticWorkoutConsentScope? {
        (await resolvedAutomaticWorkoutScope())?.scope
    }

    func enableAutomaticWorkoutDelivery(ifCurrent scope: AutomaticWorkoutConsentScope) async -> Bool {
        guard let current = await automaticWorkoutDraftScope(), current == scope,
              automaticWorkoutConsentStore.accept(scope) != nil else { return false }
        preferences.automaticWorkoutTelegramEnabled = true
        return true
    }

    func disableAutomaticWorkoutDelivery() {
        preferences.automaticWorkoutTelegramEnabled = false
    }

    func prepareForReset() {
        resetGeneration &+= 1
        telegramSecretRevision &+= 1
        automaticWorkoutConsentStore.invalidate()
        preferences.automaticWorkoutTelegramEnabled = false
    }

    func handleAutomaticWorkoutLifecycleEvent() async {
        automaticWorkoutObserverController?.refreshRegistration()
    }

    func currentAutomaticWorkoutConfiguration() async -> AutomaticWorkoutDeliveryConfiguration? {
        guard preferences.automaticWorkoutTelegramEnabled,
              let resolved = await resolvedAutomaticWorkoutScope(),
              preferences.automaticWorkoutTelegramEnabled,
              let record = automaticWorkoutConsentStore.currentRecord(for: resolved.scope) else { return nil }
        return AutomaticWorkoutDeliveryConfiguration(
            scopeID: "\(resolved.scope.id):\(record.activationID.uuidString)",
            activationDate: record.acceptedAt,
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }

    func currentAutomaticWorkoutTelegramCredentials() async -> AutomaticWorkoutTelegramCredentials? {
        guard preferences.automaticWorkoutTelegramEnabled,
              let resolved = await resolvedAutomaticWorkoutScope(),
              preferences.automaticWorkoutTelegramEnabled,
              let record = automaticWorkoutConsentStore.currentRecord(for: resolved.scope) else { return nil }
        return AutomaticWorkoutTelegramCredentials(
            scopeID: "\(resolved.scope.id):\(record.activationID.uuidString)",
            credentials: TelegramCredentials(
                botToken: resolved.botToken,
                chatID: resolved.scope.chatID,
                verbosity: .standard,
                includeGitHubLink: false,
                messageThreadID: resolved.scope.messageThreadID
            )
        )
    }

    private struct ResolvedAutomaticWorkoutScope {
        let scope: AutomaticWorkoutConsentScope
        let botToken: String
    }

    /// Resolves the Keychain-backed target as one snapshot. Both Keychain
    /// reads suspend, so the preference and secret revisions are checked
    /// again before any consent scope or credentials can escape.
    private func resolvedAutomaticWorkoutScope() async -> ResolvedAutomaticWorkoutScope? {
        let preferenceRevision = preferences.automaticWorkoutConfigurationRevision
        let secretRevision = telegramSecretRevision
        let threadID = preferences.telegramThreadId
        guard preferences.telegramExportEnabled,
              preferences.enabledCategoryIds.contains("workouts"),
              pendingTelegramSecretEdits == 0,
              failedTelegramSecretKeys.isEmpty,
              let bot = (try? await secrets.get("tg_bot_token")) ?? nil, !bot.isEmpty,
              let chat = (try? await secrets.get("tg_chat_id")) ?? nil, !chat.isEmpty,
              preferenceRevision == preferences.automaticWorkoutConfigurationRevision,
              secretRevision == telegramSecretRevision,
              preferences.telegramExportEnabled,
              preferences.enabledCategoryIds.contains("workouts"),
              preferences.telegramThreadId == threadID,
              pendingTelegramSecretEdits == 0,
              failedTelegramSecretKeys.isEmpty else { return nil }
        return ResolvedAutomaticWorkoutScope(
            scope: AutomaticWorkoutConsentScope(
                chatID: chat,
                messageThreadID: threadID,
                botToken: bot
            ),
            botToken: bot
        )
    }
}
