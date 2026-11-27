import Foundation
import HealthCore

enum WebhookTestStatus: Equatable {
    case idle
    case sending
    case delivered(host: String, statusCode: Int)
    case failed(String)
}

@MainActor
final class WebhookDestinationModel: ObservableObject {
    typealias TestSender = @Sendable (WebhookConfiguration, String) async throws -> Int

    enum ConsentStatus: Equatable {
        case current
        case reviewRequired
    }

    static let loadErrorMessage = "Could not read the webhook settings from Keychain. Go back and open Webhook again."

    @Published var endpoint: String { didSet { draftChanged() } }
    @Published var token: String { didSet { draftChanged() } }
    @Published var tokenHeader: String { didSet { draftChanged() } }
    @Published private(set) var testStatus: WebhookTestStatus
    @Published private(set) var saveError: String?
    @Published private(set) var loadError: String?
    @Published var presentedConsent: HealthExportConsentScope?
    @Published private(set) var consentScope: HealthExportConsentScope?
    @Published private(set) var consentIsCurrent = false
    @Published private(set) var stored: WebhookSettingsDraft?
    @Published private(set) var loaded: Bool

    private let sendTestRequest: TestSender
    private let appVersion: String
    private var container: AppContainer?
    private var generation: UInt64 = 0
    private var testRun = 0
    private var applyingLoad = false

    init(
        initialDraft: WebhookSettingsDraft? = nil,
        initialTestStatus: WebhookTestStatus = .idle,
        appVersion: String = WebhookDestinationModel.bundleVersion,
        sendTest: @escaping TestSender
    ) {
        let draft = initialDraft ?? .empty
        _endpoint = Published(initialValue: draft.endpoint)
        _token = Published(initialValue: draft.token)
        _tokenHeader = Published(initialValue: draft.tokenHeader)
        _testStatus = Published(initialValue: initialTestStatus)
        _loaded = Published(initialValue: initialDraft != nil)
        self.appVersion = appVersion
        self.sendTestRequest = sendTest
    }

    nonisolated static var bundleVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    var draft: WebhookSettingsDraft {
        WebhookSettingsDraft(endpoint: endpoint, token: token, tokenHeader: tokenHeader)
    }

    var validatedConfiguration: WebhookConfiguration? {
        try? draft.configuration()
    }

    var endpointValidationMessage: String? {
        guard let error = draft.validationError, error != .invalidToken else { return nil }
        return error.localizedDescription
    }

    var tokenValidationMessage: String? {
        guard draft.validationError == .invalidToken else { return nil }
        return WebhookConfigurationError.invalidToken.localizedDescription
    }

    var canSendTest: Bool {
        validatedConfiguration != nil && testStatus != .sending
    }

    var canContinue: Bool {
        loaded && validatedConfiguration != nil
    }

    var hasStoredSettings: Bool {
        stored != nil
    }

    var consentStatus: ConsentStatus? {
        guard consentScope != nil else { return nil }
        guard consentIsCurrent,
              let draftIdentity = draft.consentIdentity,
              draftIdentity == stored?.consentIdentity else { return .reviewRequired }
        return .current
    }

    func attach(_ container: AppContainer) {
        guard self.container == nil else { return }
        self.container = container
        generation = container.resetGeneration
    }

    func load() async {
        guard let container else { return }
        if loaded && generation == container.resetGeneration {
            await refresh()
            return
        }
        let currentGeneration = container.resetGeneration
        do {
            let value = try await container.loadWebhookSettings()
            let draft = value ?? .empty
            applyingLoad = true
            endpoint = draft.endpoint
            token = draft.token
            tokenHeader = draft.tokenHeader
            applyingLoad = false
            stored = value
            testRun += 1
            testStatus = .idle
            saveError = nil
            loadError = nil
            presentedConsent = nil
            generation = currentGeneration
            loaded = true
            await refresh()
        } catch {
            loaded = false
            loadError = Self.loadErrorMessage
        }
    }

    func sendTest() async {
        guard let configuration = validatedConfiguration, testStatus != .sending else { return }
        testRun += 1
        let run = testRun
        testStatus = .sending
        let result: WebhookTestStatus
        do {
            let status = try await sendTestRequest(configuration, appVersion)
            result = .delivered(host: configuration.host, statusCode: status)
        } catch {
            result = .failed(error.localizedDescription)
        }
        guard run == testRun else { return }
        testStatus = result
    }

    func continueToConsent() async {
        guard canContinue, await persist() else { return }
        await refresh()
        guard let scope = consentScope else {
            saveError = "Turn on at least one category to continue."
            return
        }
        presentedConsent = scope
    }

    func reviewConsent() async {
        await continueToConsent()
    }

    func allowConsent(_ scope: HealthExportConsentScope) async {
        guard let container else { return }
        _ = await container.acceptConsentIfCurrent(scope)
        presentedConsent = nil
        await refresh()
    }

    func declineConsent() {
        presentedConsent = nil
    }

    func remove() async {
        guard let container else { return }
        await container.clearWebhookSettings()
        endpoint = ""
        token = ""
        tokenHeader = WebhookConfiguration.defaultTokenHeader
        testStatus = .idle
        stored = nil
        consentScope = nil
        consentIsCurrent = false
    }

    func leave() {
        guard loaded, loadError == nil, let container else { return }
        container.applyWebhookDraftOnLeave(draft, stored: stored, generation: generation)
    }

    private func persist() async -> Bool {
        guard let container else { return false }
        do {
            let configuration = try await container.saveWebhookSettings(
                endpoint: endpoint,
                token: token,
                tokenHeader: tokenHeader
            )
            stored = WebhookSettingsDraft(
                endpoint: configuration.endpoint.absoluteString,
                token: configuration.token ?? "",
                tokenHeader: configuration.tokenHeader
            )
            saveError = nil
            return true
        } catch let error as WebhookConfigurationError {
            saveError = error.localizedDescription
        } catch {
            saveError = "Could not save to Keychain. Try again."
        }
        return false
    }

    private func refresh() async {
        guard let container else { return }
        await container.webhookWritesSettled()
        if let result = try? Optional(await container.loadWebhookSettings()) {
            stored = result
        }
        consentScope = await container.webhookConsentScope()
        consentIsCurrent = await container.webhookExportIsReady()
    }

    private func draftChanged() {
        guard !applyingLoad else { return }
        testRun += 1
        if testStatus != .idle { testStatus = .idle }
        if saveError != nil { saveError = nil }
    }
}
