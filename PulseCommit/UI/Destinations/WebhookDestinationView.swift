import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HealthCore

struct WebhookDestinationView: View {
    typealias TestSender = @Sendable (WebhookConfiguration, String) async throws -> Int

    enum TestStatus: Equatable {
        case idle
        case sending
        case delivered(host: String, statusCode: Int)
        case failed(String)
    }

    @EnvironmentObject var container: AppContainer
    private let sendTestRequest: TestSender?
    private let initialScrollAnchor: String?

    @State private var endpoint = ""
    @State private var tokenHeader = WebhookConfiguration.defaultTokenHeader
    @State private var token = ""
    @State private var showToken = false
    @State private var loaded = false
    @State private var testStatus: TestStatus
    @State private var saveError: String?
    @State private var presentedConsent: HealthExportConsentScope?
    @State private var consentScope: HealthExportConsentScope?
    @State private var consentRefresh = 0
    @State private var copied = false
    @State private var hasStoredSettings = false
    @State private var storedEndpoint: String?

    init(
        initialDraft: WebhookSettingsDraft? = nil,
        initialTestStatus: TestStatus = .idle,
        initialScrollAnchor: String? = nil,
        sendTest: TestSender? = nil
    ) {
        self.sendTestRequest = sendTest
        _testStatus = State(initialValue: initialTestStatus)
        self.initialScrollAnchor = initialScrollAnchor
        if let initialDraft {
            _endpoint = State(initialValue: initialDraft.endpoint)
            _token = State(initialValue: initialDraft.token)
            _tokenHeader = State(initialValue: initialDraft.tokenHeader)
            _loaded = State(initialValue: true)
        }
    }

    static let liveSendTest: TestSender = { configuration, appVersion in
        try await WebhookSink(configuration: configuration, session: EphemeralAPISession.shared)
            .sendTest(appVersion: appVersion)
    }

    private var draft: WebhookSettingsDraft {
        WebhookSettingsDraft(endpoint: endpoint, token: token, tokenHeader: tokenHeader)
    }

    private var validatedConfiguration: WebhookConfiguration? {
        try? draft.configuration()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    endpointCard
                    tokenCard
                    if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        noTokenWarning
                    }
                    payloadCard
                    testCard.id("test")
                    continueButton
                    consentCard
                    removeButton
                }
                .padding(16)
            }
            .onAppear {
                if let initialScrollAnchor { proxy.scrollTo(initialScrollAnchor, anchor: .center) }
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Webhook")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        .onDisappear(perform: persistIfValid)
        .onChange(of: endpoint) { _, _ in resetTestStatus() }
        .onChange(of: token) { _, _ in resetTestStatus() }
        .onChange(of: tokenHeader) { _, _ in resetTestStatus() }
        .sheet(item: $presentedConsent) { scope in
            HealthExportConsentSheet(
                scope: scope,
                onAllow: {
                    Task { @MainActor in
                        if await container.acceptConsentIfCurrent(scope) { consentRefresh += 1 }
                        presentedConsent = nil
                        await refreshConsentScope()
                    }
                },
                onDecline: { presentedConsent = nil }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ pulse remote add webhook")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
            Text("Webhook")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)
            Text("POST JSON to your own HTTPS endpoint")
                .font(.pcCaption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Endpoint URL")
            PCCard(padding: 14) {
                TextField("", text: $endpoint, prompt: Text(verbatim: "https://hooks.example.com/pulse").foregroundStyle(Theme.faint))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Endpoint URL")
                    .accessibilityIdentifier("webhook.endpoint")
            }
            if let message = draft.validationMessage {
                Text(message)
                    .font(.pcCaption)
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("webhook.validation")
            } else {
                Text("> HTTPS only. History shows the host only.")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Token", hint: "optional")
            PCCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HEADER")
                            .font(.pcLabel)
                            .tracking(1.5)
                            .foregroundStyle(Theme.dim)
                        TextField("", text: $tokenHeader, prompt: Text(verbatim: WebhookConfiguration.defaultTokenHeader).foregroundStyle(Theme.faint))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.pcMonoDetail)
                            .foregroundStyle(Theme.text)
                            .accessibilityLabel("Header name")
                            .accessibilityIdentifier("webhook.header")
                        Text(WebhookTokenFormatting.headerPreview(header: tokenHeader))
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.dim)
                    }
                    Divider().background(Theme.divider)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("TOKEN")
                                .font(.pcLabel)
                                .tracking(1.5)
                                .foregroundStyle(Theme.dim)
                            Spacer()
                            if !token.isEmpty {
                                Button(showToken ? "Hide" : "Show") { showToken.toggle() }
                                    .font(.pcCaption)
                                    .foregroundStyle(Theme.accent)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .buttonStyle(.plain)
                                Button(copied ? "Copied" : "Copy") { copyToken() }
                                    .font(.pcCaption)
                                    .foregroundStyle(Theme.accent)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                                    .buttonStyle(.plain)
                            }
                        }
                        Text(token.isEmpty ? "none" : (showToken ? token : WebhookTokenFormatting.masked(token)))
                            .font(.pcMonoDetail)
                            .foregroundStyle(token.isEmpty ? Theme.muted : Theme.text)
                            .lineLimit(showToken ? nil : 1)
                            .textSelection(.disabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(WebhookTokenFormatting.accessibilityLabel(token: token, revealed: showToken))
                            .accessibilityIdentifier("webhook.token")
                        HStack(spacing: 8) {
                            smallButton("Generate token", systemImage: "wand.and.stars") {
                                token = WebhookConfiguration.generateToken()
                                showToken = false
                            }
                            smallButton("Paste token", systemImage: "doc.on.clipboard") {
                                if let pasted = UIPasteboard.general.string {
                                    token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                    showToken = false
                                }
                            }
                            if !token.isEmpty {
                                Button {
                                    token = ""
                                    showToken = false
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Theme.error)
                                        .frame(width: 44, height: 44)
                                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.elevated))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove token")
                            }
                        }
                    }
                }
            }
        }
    }

    private func smallButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.pcCaption.weight(.semibold))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.elevated))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var noTokenWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warn)
            Text("No token. Anyone who knows this URL can post to it.")
                .font(.pcCaption)
                .foregroundStyle(Theme.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warn.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warn.opacity(0.4), lineWidth: 1))
        .accessibilityIdentifier("webhook.noTokenWarning")
    }

    private var payloadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Payload", hint: "1 request per day")
            PCCodeBlock(content: WebhookTokenFormatting.payloadPreview(header: tokenHeader, hasToken: !token.isEmpty))
        }
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Test")
            PCCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sends {\"event_type\": \"test\"} with no Health data. No export consent needed.")
                        .font(.pcCaption)
                        .foregroundStyle(Theme.muted)
                    Button {
                        sendTest()
                    } label: {
                        Text(testStatus == .sending ? "Sending test…" : "Send test (no Health data)")
                            .font(.pcBody.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.elevated))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(validatedConfiguration == nil || testStatus == .sending)
                    .opacity(validatedConfiguration == nil ? 0.45 : 1)
                    testStatusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var testStatusLine: some View {
        switch testStatus {
        case .idle, .sending:
            Text("> last test: none")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
        case .delivered(let host, let statusCode):
            Text("> last test: \(host) · HTTP \(statusCode)")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.success)
                .accessibilityIdentifier("webhook.testStatus")
        case .failed(let message):
            Text("> last test: \(message)")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.error)
                .accessibilityIdentifier("webhook.testStatus")
        }
    }

    private var continueButton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Continue") { continueToConsent() }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(validatedConfiguration == nil)
                .opacity(validatedConfiguration == nil ? 0.45 : 1)
            if let saveError {
                Text(saveError)
                    .font(.pcCaption)
                    .foregroundStyle(Theme.error)
            }
        }
    }

    @ViewBuilder
    private var consentCard: some View {
        if let scope = consentScope {
            Button {
                presentedConsent = scope
            } label: {
                PCCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Export consent")
                                .font(.pcBody)
                                .foregroundStyle(Theme.text)
                            Text(container.consentStore.hasCurrentConsent(for: scope) ? "CURRENT" : "REVIEW REQUIRED")
                                .font(.pcCaptionMono)
                                .foregroundStyle(container.consentStore.hasCurrentConsent(for: scope) ? Theme.success : Theme.warn)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .buttonStyle(.plain)
            .id(consentRefresh)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if hasStoredSettings {
            Button("Remove webhook") {
                Task { @MainActor in
                    await container.clearWebhookSettings()
                    endpoint = ""
                    token = ""
                    tokenHeader = WebhookConfiguration.defaultTokenHeader
                    testStatus = .idle
                    consentScope = nil
                    hasStoredSettings = false
                    storedEndpoint = nil
                }
            }
            .font(.pcBody)
            .foregroundStyle(Theme.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .buttonStyle(.plain)
        }
    }

    private func resetTestStatus() {
        guard loaded, testStatus != .sending else { return }
        testStatus = .idle
        saveError = nil
        copied = false
    }

    private func copyToken() {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: token]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
        copied = true
    }

    private func sendTest() {
        guard let configuration = validatedConfiguration else { return }
        let submitted = draft
        testStatus = .sending
        Task { @MainActor in
            await persist(submitted)
            do {
                let status = try await (sendTestRequest ?? container.webhookTestSender)(configuration, Self.appVersion)
                guard draft == submitted else { return }
                testStatus = .delivered(host: configuration.host, statusCode: status)
            } catch {
                guard draft == submitted else { return }
                testStatus = .failed(error.localizedDescription)
            }
        }
    }

    private func continueToConsent() {
        let submitted = draft
        Task { @MainActor in
            guard await persist(submitted) else { return }
            container.preferences.webhookExportEnabled = true
            await refreshConsentScope()
            guard let scope = consentScope else {
                saveError = "Turn on at least one category to continue."
                return
            }
            presentedConsent = scope
        }
    }

    @discardableResult
    private func persist(_ submitted: WebhookSettingsDraft) async -> Bool {
        do {
            try await container.saveWebhookSettings(
                endpoint: submitted.endpoint,
                token: submitted.token,
                tokenHeader: submitted.tokenHeader
            )
            saveError = nil
            hasStoredSettings = true
            storedEndpoint = submitted.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            return true
        } catch let error as WebhookConfigurationError {
            saveError = error.localizedDescription
        } catch {
            saveError = "Could not save to Keychain. Try again."
        }
        return false
    }

    private func persistIfValid() {
        guard loaded else { return }
        let submitted = draft
        container.disableWebhookIfInvalidChange(draft: submitted, storedEndpoint: storedEndpoint)
        Task { @MainActor in await container.applyWebhookDraftOnLeave(submitted) }
    }

    private func refreshConsentScope() async {
        consentScope = await container.currentConsentScope(for: .webhook)
        let stored = await container.storedWebhookSettings()
        hasStoredSettings = stored != nil
        storedEndpoint = stored?.endpoint
    }

    private func loadIfNeeded() {
        guard !loaded else {
            Task { @MainActor in await refreshConsentScope() }
            return
        }
        Task { @MainActor in
            let stored = await container.storedWebhookSettings() ?? .empty
            endpoint = stored.endpoint
            token = stored.token
            tokenHeader = stored.tokenHeader
            loaded = true
            await refreshConsentScope()
        }
    }

    private static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}

enum WebhookTokenFormatting {
    static func headerPreview(header: String) -> String {
        let name = header.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = name.isEmpty ? WebhookConfiguration.defaultTokenHeader : name
        if resolved.lowercased() == "authorization" {
            return "Sent as \(resolved): Bearer <token>"
        }
        return "Sent as \(resolved): <token>"
    }

    static func accessibilityLabel(token: String, revealed: Bool) -> String {
        if token.isEmpty { return "Token, none" }
        if revealed { return "Token, shown" }
        guard token.count > 8 else { return "Token, hidden" }
        return "Token, hidden, ends in \(token.suffix(4))"
    }

    static func masked(_ token: String) -> String {
        guard token.count > 8 else { return String(repeating: "•", count: 12) }
        return String(repeating: "•", count: 12) + token.suffix(4)
    }

    static func payloadPreview(header: String, hasToken: Bool) -> String {
        var lines = [
            "POST · Content-Type: application/json",
            "Idempotency-Key: pc-2026-11-23-3f9a1c0b7e2d"
        ]
        if hasToken {
            lines.append(headerPreview(header: header).replacingOccurrences(of: "Sent as ", with: ""))
        }
        lines.append(contentsOf: [
            "",
            "{",
            "  \"schema_version\": \"1.0\",",
            "  \"event_type\": \"daily_export\",",
            "  \"date\": \"2026-11-23\",",
            "  \"idempotency_key\": \"pc-2026-11-23-…\",",
            "  \"summary\": { …summary.json… },",
            "  \"summary_markdown\": \"…\",",
            "  \"files\": [{ \"path\": …, \"bytes\": … }]",
            "}"
        ])
        return lines.joined(separator: "\n")
    }
}
