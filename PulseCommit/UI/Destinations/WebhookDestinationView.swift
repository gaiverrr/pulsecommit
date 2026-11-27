import SwiftUI
import UIKit
import UniformTypeIdentifiers
import HealthCore

struct WebhookDestinationView: View {
    typealias TestSender = WebhookDestinationModel.TestSender
    typealias TestStatus = WebhookTestStatus

    @EnvironmentObject var container: AppContainer
    @StateObject private var model: WebhookDestinationModel
    private let initialScrollAnchor: String?

    @State private var showToken = false
    @State private var copied = false

    init(
        initialDraft: WebhookSettingsDraft? = nil,
        initialTestStatus: TestStatus = .idle,
        initialScrollAnchor: String? = nil,
        sendTest: @escaping TestSender = WebhookDestinationView.liveSendTest
    ) {
        _model = StateObject(wrappedValue: WebhookDestinationModel(
            initialDraft: initialDraft,
            initialTestStatus: initialTestStatus,
            sendTest: sendTest
        ))
        self.initialScrollAnchor = initialScrollAnchor
    }

    static let liveSendTest: TestSender = { configuration, appVersion in
        try await WebhookSink(configuration: configuration, session: EphemeralAPISession.shared)
            .sendTest(appVersion: appVersion)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 20) {
                    header
                    endpointCard
                    tokenCard
                    if model.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
        .onAppear {
            model.attach(container)
            Task { await model.load() }
        }
        .onDisappear { model.leave() }
        .onChange(of: model.endpoint) { _, _ in copied = false }
        .onChange(of: model.token) { _, _ in copied = false }
        .onChange(of: model.tokenHeader) { _, _ in copied = false }
        .sheet(item: $model.presentedConsent) { scope in
            HealthExportConsentSheet(
                scope: scope,
                onAllow: {
                    Task { @MainActor in await model.allowConsent(scope) }
                },
                onDecline: { model.declineConsent() }
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
            if let loadError = model.loadError {
                Text(loadError)
                    .font(.pcCaption)
                    .foregroundStyle(Theme.error)
                    .accessibilityIdentifier("webhook.loadError")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Endpoint URL")
            PCCard(padding: 14) {
                TextField("", text: $model.endpoint, prompt: Text(verbatim: "https://hooks.example.com/pulse").foregroundStyle(Theme.faint))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.pcMonoDetail)
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Endpoint URL")
                    .accessibilityIdentifier("webhook.endpoint")
            }
            if let message = model.endpointValidationMessage {
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
                        TextField("", text: $model.tokenHeader, prompt: Text(verbatim: WebhookConfiguration.defaultTokenHeader).foregroundStyle(Theme.faint))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.pcMonoDetail)
                            .foregroundStyle(Theme.text)
                            .accessibilityLabel("Header name")
                            .accessibilityIdentifier("webhook.header")
                        Text(WebhookTokenFormatting.headerPreview(header: model.tokenHeader))
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
                            if !model.token.isEmpty {
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
                        Text(model.token.isEmpty ? "none" : (showToken ? model.token : WebhookTokenFormatting.masked(model.token)))
                            .font(.pcMonoDetail)
                            .foregroundStyle(model.token.isEmpty ? Theme.muted : Theme.text)
                            .lineLimit(showToken ? nil : 1)
                            .textSelection(.disabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(WebhookTokenFormatting.accessibilityLabel(token: model.token, revealed: showToken))
                            .accessibilityIdentifier("webhook.token")
                        HStack(spacing: 8) {
                            smallButton("Generate token", systemImage: "wand.and.stars") {
                                model.token = WebhookConfiguration.generateToken()
                                showToken = false
                            }
                            smallButton("Paste token", systemImage: "doc.on.clipboard") {
                                if let pasted = UIPasteboard.general.string {
                                    model.token = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                                    showToken = false
                                }
                            }
                            if !model.token.isEmpty {
                                Button {
                                    model.token = ""
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
                        if let message = model.tokenValidationMessage {
                            Text(message)
                                .font(.pcCaption)
                                .foregroundStyle(Theme.error)
                                .accessibilityIdentifier("webhook.tokenValidation")
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
            PCCodeBlock(content: WebhookTokenFormatting.payloadPreview(header: model.tokenHeader, hasToken: !model.token.isEmpty))
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
                        Task { @MainActor in await model.sendTest() }
                    } label: {
                        Text(model.testStatus == .sending ? "Sending test…" : "Send test (no Health data)")
                            .font(.pcBody.weight(.semibold))
                            .foregroundStyle(Theme.text)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.elevated))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canSendTest)
                    .opacity(model.validatedConfiguration == nil ? 0.45 : 1)
                    testStatusLine
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var testStatusLine: some View {
        switch model.testStatus {
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
            Button("Continue") {
                Task { @MainActor in await model.continueToConsent() }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(!model.canContinue)
            .opacity(model.canContinue ? 1 : 0.45)
            if let saveError = model.saveError {
                Text(saveError)
                    .font(.pcCaption)
                    .foregroundStyle(Theme.error)
            }
        }
    }

    @ViewBuilder
    private var consentCard: some View {
        if let status = model.consentStatus {
            Button {
                Task { @MainActor in await model.reviewConsent() }
            } label: {
                PCCard {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Export consent")
                                .font(.pcBody)
                                .foregroundStyle(Theme.text)
                            Text(status == .current ? "CURRENT" : "REVIEW REQUIRED")
                                .font(.pcCaptionMono)
                                .foregroundStyle(status == .current ? Theme.success : Theme.warn)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(Theme.faint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if model.hasStoredSettings {
            Button("Remove webhook") {
                Task { @MainActor in await model.remove() }
            }
            .font(.pcBody)
            .foregroundStyle(Theme.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .buttonStyle(.plain)
        }
    }

    private func copyToken() {
        UIPasteboard.general.setItems(
            [[UTType.plainText.identifier: model.token]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)]
        )
        copied = true
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
