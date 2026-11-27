import Foundation
import HealthCore

enum WebhookSecretKeys {
    static let endpoint = "webhook_url"
    static let token = "webhook_token"
    static let tokenHeader = "webhook_token_header"
    static let all = [endpoint, token, tokenHeader]
}

struct WebhookSettingsDraft: Equatable, Sendable {
    var endpoint: String
    var token: String
    var tokenHeader: String

    static let empty = WebhookSettingsDraft(
        endpoint: "",
        token: "",
        tokenHeader: WebhookConfiguration.defaultTokenHeader
    )

    var validationMessage: String? {
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            _ = try configuration()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    var validationError: WebhookConfigurationError? {
        guard !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            _ = try configuration()
            return nil
        } catch let error as WebhookConfigurationError {
            return error
        } catch {
            return .missingHost
        }
    }

    var normalized: WebhookSettingsDraft {
        let header = tokenHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        return WebhookSettingsDraft(
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            tokenHeader: header.isEmpty ? WebhookConfiguration.defaultTokenHeader : header
        )
    }

    var consentIdentity: WebhookConsentIdentity? {
        try? configuration().consentIdentity
    }

    func isInvalidChange(from stored: WebhookSettingsDraft?) -> Bool {
        guard let stored,
              !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              normalized != stored.normalized else { return false }
        return (try? configuration()) == nil
    }

    func configuration() throws -> WebhookConfiguration {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { throw WebhookConfigurationError.missingHost }
        let header = tokenHeader.trimmingCharacters(in: .whitespacesAndNewlines)
        return try WebhookConfiguration(
            endpoint: url,
            token: token,
            tokenHeader: header.isEmpty ? WebhookConfiguration.defaultTokenHeader : header
        )
    }
}

extension AppContainer {
    static let resettableSecretKeys = [KeychainTokenVault.storageKey, "tg_bot_token", "tg_chat_id"] + WebhookSecretKeys.all

    func loadWebhookSettings() async throws -> WebhookSettingsDraft? {
        guard let endpoint = try await secrets.get(WebhookSecretKeys.endpoint), !endpoint.isEmpty else { return nil }
        let token = try await secrets.get(WebhookSecretKeys.token)
        let header = try await secrets.get(WebhookSecretKeys.tokenHeader)
        return WebhookSettingsDraft(
            endpoint: endpoint,
            token: token ?? "",
            tokenHeader: header ?? WebhookConfiguration.defaultTokenHeader
        )
    }

    func storedWebhookSettings() async -> WebhookSettingsDraft? {
        (try? await loadWebhookSettings()) ?? nil
    }

    func currentWebhookConfiguration() async -> WebhookConfiguration? {
        try? await storedWebhookSettings()?.configuration()
    }

    @discardableResult
    func saveWebhookSettings(endpoint: String, token: String, tokenHeader: String) async throws -> WebhookConfiguration {
        let configuration = try WebhookSettingsDraft(
            endpoint: endpoint,
            token: token,
            tokenHeader: tokenHeader
        ).configuration()
        try await enqueueWebhookWrite { try await self.writeWebhookSettings(configuration) }.value
        return configuration
    }

    func clearWebhookSettings() async {
        _ = try? await enqueueWebhookWrite { await self.removeWebhookSettings() }.value
    }

    func webhookWritesSettled() async {
        while let pending = lastWebhookWrite {
            await pending.value
            if lastWebhookWrite == pending { return }
        }
    }

    func applyWebhookDraftOnLeave(_ draft: WebhookSettingsDraft, stored: WebhookSettingsDraft?, generation: UInt64) {
        guard generation == resetGeneration else { return }
        if draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard stored != nil else { return }
            enqueueWebhookWrite {
                guard generation == self.resetGeneration else { return }
                await self.removeWebhookSettings()
            }
            return
        }
        guard let configuration = try? draft.configuration() else {
            if draft.isInvalidChange(from: stored) {
                preferences.webhookPausedByInvalidEdit = true
                noteWebhookChanged()
            }
            return
        }
        if let stored, stored.normalized == draft.normalized {
            if preferences.webhookPausedByInvalidEdit {
                preferences.webhookPausedByInvalidEdit = false
                noteWebhookChanged()
            }
            return
        }
        enqueueWebhookWrite {
            guard generation == self.resetGeneration else { return }
            try await self.writeWebhookSettings(configuration)
        }
    }

    @discardableResult
    private func enqueueWebhookWrite<T: Sendable>(
        _ operation: @escaping @MainActor () async throws -> T
    ) -> Task<T, Error> {
        let previous = lastWebhookWrite
        let task = Task { @MainActor in
            await previous?.value
            return try await operation()
        }
        lastWebhookWrite = Task { @MainActor in _ = try? await task.value }
        return task
    }

    private func writeWebhookSettings(_ configuration: WebhookConfiguration) async throws {
        defer { noteWebhookChanged() }
        let previous: WebhookSettingsDraft?
        let readFailed: Bool
        do {
            previous = try await loadWebhookSettings()
            readFailed = false
        } catch {
            previous = nil
            readFailed = true
        }
        let newEndpoint = configuration.endpoint.absoluteString
        if readFailed || previous?.consentIdentity != configuration.consentIdentity {
            consentStore.invalidate(.webhook)
        }
        let endpointChanges = readFailed || previous?.endpoint != newEndpoint
        do {
            if endpointChanges {
                try await secrets.set(nil, for: WebhookSecretKeys.endpoint)
            }
            try await secrets.set(configuration.token, for: WebhookSecretKeys.token)
            try await secrets.set(configuration.tokenHeader, for: WebhookSecretKeys.tokenHeader)
            if endpointChanges {
                try await secrets.set(newEndpoint, for: WebhookSecretKeys.endpoint)
            }
        } catch {
            await restoreWebhookSettings(previous)
            throw error
        }
        preferences.webhookPausedByInvalidEdit = false
    }

    private func restoreWebhookSettings(_ previous: WebhookSettingsDraft?) async {
        guard let previous else {
            try? await secrets.set(nil, for: WebhookSecretKeys.endpoint)
            return
        }
        do {
            try await secrets.set(previous.token.isEmpty ? nil : previous.token, for: WebhookSecretKeys.token)
            try await secrets.set(previous.tokenHeader, for: WebhookSecretKeys.tokenHeader)
            try await secrets.set(previous.endpoint, for: WebhookSecretKeys.endpoint)
        } catch {
            try? await secrets.set(nil, for: WebhookSecretKeys.endpoint)
        }
    }

    private func removeWebhookSettings() async {
        defer { noteWebhookChanged() }
        consentStore.invalidate(.webhook)
        preferences.webhookExportEnabled = false
        preferences.webhookPausedByInvalidEdit = false
        for key in WebhookSecretKeys.all {
            try? await secrets.set(nil, for: key)
        }
    }

    func webhookConsentScope(categoryIDs: Set<String>? = nil) async -> HealthExportConsentScope? {
        let categories = categoryIDs ?? preferences.enabledCategoryIds
        guard !categories.isEmpty, let configuration = await currentWebhookConfiguration() else { return nil }
        return HealthExportConsentScope(
            destination: HealthExportDestinationIdentity(webhook: configuration.consentIdentity),
            enabledCategoryIds: categories
        )
    }

    private var webhookEnrolled: Bool {
        preferences.webhookExportEnabled && !preferences.webhookPausedByInvalidEdit
    }

    func configuredWebhookTarget() async -> (configuration: WebhookConfiguration, requirement: ConsentRequirement)? {
        guard webhookEnrolled,
              let configuration = await currentWebhookConfiguration(),
              webhookEnrolled else { return nil }
        return (
            configuration,
            ConsentRequirement(
                sinkID: WebhookDestinationSink.sinkID,
                destination: HealthExportDestinationIdentity(webhook: configuration.consentIdentity)
            )
        )
    }

    func webhookExportIsConfigured() async -> Bool {
        await configuredWebhookTarget() != nil
    }

    func webhookExportIsReady() async -> Bool {
        let categories = preferences.enabledCategoryIds
        guard !categories.isEmpty, let target = await configuredWebhookTarget() else { return false }
        return consentStore.hasCurrentConsent(for: target.requirement.scope(for: categories))
    }

    func webhookTargetMatches(_ destination: HealthExportDestinationIdentity) async -> Bool {
        guard let target = await configuredWebhookTarget() else { return false }
        return target.requirement.destination == destination
    }
}
