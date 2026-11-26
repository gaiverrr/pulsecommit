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

    func isInvalidChange(from storedEndpoint: String?) -> Bool {
        let submitted = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let storedEndpoint, !submitted.isEmpty, submitted != storedEndpoint else { return false }
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

    func storedWebhookSettings() async -> WebhookSettingsDraft? {
        guard let endpoint = (try? await secrets.get(WebhookSecretKeys.endpoint)) ?? nil,
              !endpoint.isEmpty else { return nil }
        let token = (try? await secrets.get(WebhookSecretKeys.token)) ?? nil
        let header = (try? await secrets.get(WebhookSecretKeys.tokenHeader)) ?? nil
        return WebhookSettingsDraft(
            endpoint: endpoint,
            token: token ?? "",
            tokenHeader: header ?? WebhookConfiguration.defaultTokenHeader
        )
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
        try await secrets.set(configuration.endpoint.absoluteString, for: WebhookSecretKeys.endpoint)
        try await secrets.set(configuration.token, for: WebhookSecretKeys.token)
        try await secrets.set(configuration.tokenHeader, for: WebhookSecretKeys.tokenHeader)
        return configuration
    }

    func clearWebhookSettings() async {
        consentStore.invalidate(.webhook)
        for key in WebhookSecretKeys.all {
            try? await secrets.set(nil, for: key)
        }
    }

    func webhookConsentScope(categoryIDs: Set<String>? = nil) async -> HealthExportConsentScope? {
        await webhookTarget(categoryIDs: categoryIDs)?.scope
    }

    func configuredWebhookTarget() async -> (configuration: WebhookConfiguration, requirement: ConsentRequirement)? {
        guard let target = await webhookTarget(categoryIDs: nil) else { return nil }
        return (
            target.configuration,
            ConsentRequirement(sinkID: WebhookDestinationSink.sinkID, destination: target.scope.destination)
        )
    }

    func webhookExportIsConfigured() async -> Bool {
        await configuredWebhookTarget() != nil
    }

    @discardableResult
    func disableWebhookIfInvalidChange(draft: WebhookSettingsDraft, storedEndpoint: String?) -> Bool {
        guard draft.isInvalidChange(from: storedEndpoint) else { return false }
        preferences.webhookExportEnabled = false
        return true
    }

    func applyWebhookDraftOnLeave(_ draft: WebhookSettingsDraft) async {
        if draft.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await clearWebhookSettings()
            return
        }
        if (try? draft.configuration()) != nil {
            _ = try? await saveWebhookSettings(
                endpoint: draft.endpoint,
                token: draft.token,
                tokenHeader: draft.tokenHeader
            )
            return
        }
        if draft.isInvalidChange(from: await storedWebhookSettings()?.endpoint) {
            preferences.webhookExportEnabled = false
        }
    }

    private func webhookTarget(
        categoryIDs: Set<String>?
    ) async -> (configuration: WebhookConfiguration, scope: HealthExportConsentScope)? {
        let categories = categoryIDs ?? preferences.enabledCategoryIds
        guard !categories.isEmpty,
              preferences.webhookExportEnabled,
              let configuration = await currentWebhookConfiguration(),
              preferences.webhookExportEnabled else { return nil }
        let scope = HealthExportConsentScope(
            destination: HealthExportDestinationIdentity(webhook: configuration.consentIdentity),
            enabledCategoryIds: categories
        )
        return (configuration, scope)
    }

    func webhookExportIsReady() async -> Bool {
        guard let target = await webhookTarget(categoryIDs: nil) else { return false }
        return consentStore.hasCurrentConsent(for: target.scope)
    }

    func webhookTargetMatches(_ destination: HealthExportDestinationIdentity) async -> Bool {
        guard preferences.webhookExportEnabled,
              let configuration = await currentWebhookConfiguration(),
              preferences.webhookExportEnabled else { return false }
        return HealthExportDestinationIdentity(webhook: configuration.consentIdentity) == destination
    }
}
