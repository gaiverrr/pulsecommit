import SwiftUI
import HealthCore

// Validator lives in Validators/ChatIdValidator.swift

private enum VerbosityOption: String, Hashable, CustomStringConvertible, CaseIterable {
    case compact
    case standard
    case verbose

    var description: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .verbose: return "Verbose"
        }
    }

    init(verbosity: SummaryVerbosity) {
        switch verbosity {
        case .compact: self = .compact
        case .standard: self = .standard
        case .verbose: self = .verbose
        }
    }

    var summary: SummaryVerbosity {
        switch self {
        case .compact: return .compact
        case .standard: return .standard
        case .verbose: return .verbose
        }
    }
}

struct TelegramDestinationView: View {
    @EnvironmentObject var container: AppContainer
    let setupClient: TelegramSetupClient
    let onBackToHome: () -> Void

    @State private var botToken: String = ""
    @State private var chatID: String = ""
    @State private var threadId: String = ""
    @State private var verbosity: VerbosityOption = .standard
    @State private var loaded: Bool = false
    @State private var persistedBotToken: String?
    @State private var persistedChatID: String?
    @State private var presentedConsent: HealthExportConsentScope?
    @State private var presentedAutomaticConsent: AutomaticWorkoutConsentScope?
    @State private var automaticWorkoutEnabled = false
    @State private var automaticWorkoutState: AutomaticWorkoutCardState = .off
    @State private var consentRefresh = 0
    @State private var verifiedBotToken: String?
    @State private var verifiedBotName: String?
    @State private var setupError: String?
    @State private var testSucceeded = false
    @State private var checkingBot = false
    @State private var sendingTest = false
    @State private var showSetupHelp = false

    init(
        setupClient: TelegramSetupClient = TelegramSetupClient(),
        onBackToHome: @escaping () -> Void = {}
    ) {
        self.setupClient = setupClient
        self.onBackToHome = onBackToHome
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                setupHelpCard
                tokenCard
                chatCard
                threadCard
                connectionTestCard
                aiIngestionCard
                automaticWorkoutCard
                verbosityCard
                consentCard
                previewCard
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Telegram")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear(perform: loadIfNeeded)
        .onChange(of: botToken) { _, new in
            guard loaded else { return }
            let value = Self.trimmedNonEmpty(for: new)
            guard value != persistedBotToken else { return }
            persistedBotToken = value
            verifiedBotToken = nil
            verifiedBotName = nil
            testSucceeded = false
            setupError = nil
            container.updateTelegramSecret(value, for: "tg_bot_token")
        }
        .onChange(of: chatID) { _, new in
            guard loaded else { return }
            let value = Self.chatIdToPersist(for: new)
            guard value != persistedChatID else { return }
            persistedChatID = value
            testSucceeded = false
            setupError = nil
            container.updateTelegramSecret(value, for: "tg_chat_id")
        }
        .onChange(of: threadId) { _, new in
            guard loaded else { return }
            testSucceeded = false
            setupError = nil
            let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
            container.preferences.telegramThreadId = trimmed.isEmpty ? nil : Int(trimmed)
        }
        .onChange(of: verbosity) { _, new in
            guard loaded else { return }
            container.preferences.telegramVerbosity = new.summary.rawValue
        }
        .sheet(item: $presentedConsent) { scope in
            HealthExportConsentSheet(
                scope: scope,
                onAllow: {
                    Task { @MainActor in
                        if await container.acceptConsentIfCurrent(scope) { consentRefresh += 1 }
                        presentedConsent = nil
                    }
                },
                onDecline: { presentedConsent = nil }
            )
        }
        .sheet(item: $presentedAutomaticConsent) { scope in
            AutomaticWorkoutConsentSheet(
                scope: scope,
                onAllow: {
                    Task { @MainActor in
                        let enabled = await container.enableAutomaticWorkoutDelivery(ifCurrent: scope)
                        presentedAutomaticConsent = nil
                        automaticWorkoutEnabled = enabled
                        automaticWorkoutState = enabled ? .on : .blocked("Settings changed — review again")
                        container.automaticWorkoutObserverController?.refreshRegistration()
                    }
                },
                onDecline: { presentedAutomaticConsent = nil }
            )
        }
        .task(id: container.automaticWorkoutStateRevision) {
            guard loaded else { return }
            await refreshAutomaticWorkoutState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("$ pulse remote add telegram")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
            Text("Telegram")
                .font(.pcLargeTitle)
                .foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tokenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCCard {
                MaskedSecretField(
                    title: "Bot token",
                    placeholder: "1234567:••••••••••••••••",
                    value: $botToken
                )
            }
            Button(checkingBot ? "Checking bot…" : "Verify bot token") {
                verifyBot()
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || checkingBot || sendingTest)
            .opacity(botToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
            if let verifiedBotName {
                Text("Bot verified: @\(verifiedBotName)")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.success)
            }
        }
    }

    private var setupHelpCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "SETUP HELP")
            PCCard {
                DisclosureGroup(isExpanded: $showSetupHelp) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("1. In Telegram, open @BotFather and create a bot. Copy its token here.")
                        Text("2. Add the bot to your target group or channel, or message it in a private chat.")
                        Text("3. Enter that chat's numeric ID. For a forum topic, add its optional thread ID. A private chat ID can be found with a trusted chat-ID helper. For a supergroup link t.me/c/123…, use -100123… as the ID.")
                    }
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 8)
                } label: {
                    Text("Bot token · chat ID · optional topic")
                        .font(.pcBody)
                        .foregroundStyle(Theme.text)
                }
                .tint(Theme.accent)
            }
        }
    }

    private var chatIDValidation: ChatIdValidation {
        ChatIdValidator.validate(chatID)
    }

    private var chatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Chat id")
            PCCard(padding: 14) {
                PlainSecretField(
                    title: "Chat id",
                    placeholder: "-1001234567890",
                    value: $chatID,
                    valueColor: Theme.accent
                )
            }
            chatIDCaption
        }
    }

    @ViewBuilder
    private var chatIDCaption: some View {
        switch chatIDValidation {
        case .invalid where !chatID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            Text("Chat IDs are numbers. Supergroups and channels start with -100…")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.error)
        case .warning:
            Text("Supergroup and channel IDs start with a minus: -100…")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.warn)
        default:
            EmptyView()
        }
    }

    private var threadCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "Thread id (optional)")
            PCCard(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("", text: $threadId, prompt: Text("42").foregroundStyle(Theme.faint))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.numbersAndPunctuation)
                        .font(.pcMonoDetail)
                        .foregroundStyle(Theme.accent)
                    Text("> Required only for posting into a forum topic. Get it from the Telegram URL when you open the thread.")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var connectionTestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            PCSectionHeader(title: "TEST DELIVERY")
            PCCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Target: chat \(chatID.isEmpty ? "—" : chatID)\(validatedThreadID.map { " · topic \($0)" } ?? " · main chat")")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.text)
                    Text("Message: \(TelegramSetupClient.testMessage)")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.muted)
                    Text("This sends only the sample text shown above. It does not export Health data.")
                        .font(.pcCaption)
                        .foregroundStyle(Theme.dim)
                    Button(sendingTest ? "Sending test…" : "Send test message") {
                        sendTestMessage()
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                    .disabled(!canSendTest || sendingTest || checkingBot)
                    .opacity(canSendTest ? 1 : 0.45)
                    if let setupError {
                        Text(setupError)
                            .font(.pcCaption)
                            .foregroundStyle(Theme.error)
                            .accessibilityIdentifier("telegram.setup.error")
                    }
                    if testSucceeded {
                        Text("Test message delivered. Tap Export Now, then verify History.")
                            .font(.pcBody)
                            .foregroundStyle(Theme.success)
                        Button("Back to Home") { onBackToHome() }
                            .buttonStyle(DSPrimaryButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var aiIngestionCard: some View {
        PCCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Using an external AI agent?")
                    .font(.pcBodySemibold)
                    .foregroundStyle(Theme.text)
                Text("Delivery to Telegram does not mean an AI agent will read it. Bot-to-bot delivery may require Bot-to-Bot Communication Mode, chat admin/privacy settings, and the external agent's sender allowlist.")
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var automaticWorkoutCard: some View {
        AutomaticWorkoutDeliveryCard(
            isOn: automaticWorkoutEnabled,
            state: automaticWorkoutState,
            onToggle: setAutomaticWorkoutEnabled,
            onRetry: retryAutomaticWorkout
        )
    }

    private func setAutomaticWorkoutEnabled(_ enabled: Bool) {
        if !enabled {
            container.disableAutomaticWorkoutDelivery()
            automaticWorkoutEnabled = false
            automaticWorkoutState = .off
            container.automaticWorkoutObserverController?.refreshRegistration()
            return
        }
        Task { @MainActor in
            guard let scope = await container.automaticWorkoutDraftScope() else {
                automaticWorkoutEnabled = false
                automaticWorkoutState = .blocked("Unavailable — finish Telegram setup and enable Workouts")
                return
            }
            presentedAutomaticConsent = scope
        }
    }

    private func retryAutomaticWorkout(_ id: UUID) {
        Task { @MainActor in
            await container.automaticWorkoutCoordinator?.retryUnknown(
                workoutID: id,
                duplicateRiskAcknowledged: true
            )
            await refreshAutomaticWorkoutState()
        }
    }

    private func refreshAutomaticWorkoutState() async {
        automaticWorkoutEnabled = container.preferences.automaticWorkoutTelegramEnabled
        guard automaticWorkoutEnabled else {
            automaticWorkoutState = .off
            return
        }
        if container.preferences.automaticWorkoutRegistrationFailed {
            automaticWorkoutState = .blocked("Background registration failed — open the app to retry")
            return
        }
        guard let configuration = await container.currentAutomaticWorkoutConfiguration() else {
            automaticWorkoutEnabled = false
            automaticWorkoutState = .blocked("Unavailable — finish Telegram setup and enable Workouts")
            return
        }
        switch await container.automaticWorkoutAttempts.latest(scopeID: configuration.scopeID) {
        case .unavailable:
            automaticWorkoutState = .blocked("Delivery state unavailable — automatic sending is paused")
        case .missing:
            automaticWorkoutState = .on
        case .found(let record):
            switch record.state {
            case .delivered: automaticWorkoutState = .delivered(record.updatedAt)
            case .deliveryUnknown, .sending: automaticWorkoutState = .deliveryUnknown(record.workoutID)
            case .rejected: automaticWorkoutState = .blocked("Last delivery was rejected — Pulse Commit will retry when allowed")
            }
        }
    }

    private var validatedThreadID: Int? {
        let value = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : Int(value)
    }

    private var canSendTest: Bool {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        return loaded && verifiedBotToken == token && Self.chatIdToPersist(for: chatID) != nil &&
            (thread.isEmpty || (validatedThreadID.map { $0 > 0 } ?? false))
    }

    private func verifyBot() {
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        checkingBot = true
        setupError = nil
        Task { @MainActor in
            defer { checkingBot = false }
            do {
                let name = try await setupClient.verifyBot(token: token)
                guard botToken.trimmingCharacters(in: .whitespacesAndNewlines) == token else { return }
                verifiedBotToken = token
                verifiedBotName = name
            } catch {
                verifiedBotToken = nil
                verifiedBotName = nil
                setupError = (error as? TelegramSetupError)?.localizedDescription ?? TelegramSetupError.unexpectedResponse.localizedDescription
            }
        }
    }

    private func sendTestMessage() {
        guard canSendTest, let chat = Self.chatIdToPersist(for: chatID) else { return }
        let token = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = validatedThreadID
        sendingTest = true
        setupError = nil
        testSucceeded = false
        Task { @MainActor in
            defer { sendingTest = false }
            do {
                guard await container.telegramCredentialsMatch(botToken: token, chatID: chat) else {
                    setupError = "Could not save this bot or chat. Re-enter the token and chat ID, then try again."
                    return
                }
                guard botToken.trimmingCharacters(in: .whitespacesAndNewlines) == token,
                      Self.chatIdToPersist(for: chatID) == chat,
                      validatedThreadID == thread else { return }
                try await setupClient.sendTestMessage(token: token, chatID: chat, threadID: thread)
                guard botToken.trimmingCharacters(in: .whitespacesAndNewlines) == token,
                      Self.chatIdToPersist(for: chatID) == chat,
                      validatedThreadID == thread else { return }
                testSucceeded = true
            } catch {
                setupError = (error as? TelegramSetupError)?.localizedDescription ?? TelegramSetupError.unexpectedResponse.localizedDescription
            }
        }
    }

    private var verbosityCard: some View {
        VStack(spacing: 8) {
            PCSectionHeader(title: "Verbosity")
            PCCard(padding: 12) {
                PCSegmented(options: VerbosityOption.allCases, selection: $verbosity)
            }
        }
    }

    @ViewBuilder
    private var consentCard: some View {
        if let scope = currentConsentScope {
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

    private var currentConsentScope: HealthExportConsentScope? {
        let trimmedBot = botToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBot.isEmpty, let chat = Self.chatIdToPersist(for: chatID) else { return nil }
        let trimmedThread = threadId.trimmingCharacters(in: .whitespacesAndNewlines)
        return HealthExportConsentScope(
            destination: .telegram(chatID: chat, messageThreadID: trimmedThread.isEmpty ? nil : Int(trimmedThread)),
            enabledCategoryIds: container.preferences.enabledCategoryIds
        )
    }

    private var previewCard: some View {
        VStack(spacing: 8) {
            PCSectionHeader(title: "Preview · \(verbosity.description.lowercased())")
            PCCodeBlock(content: previewContent)
        }
    }

    private var previewContent: String {
        switch verbosity {
        case .compact:
            return """
            *Pulse Commit · 2026-05-14*
            steps 12 483 · sleep 7h 12m · 1 workout
            """
        case .standard:
            return """
            *Pulse Commit · 2026-05-14*

            steps        12 483
            distance      8.42 km
            active        612 kcal
            heart-rate    avg 71 bpm
            sleep         7h 12m
            workouts      1 (running, 38 min)
            """
        case .verbose:
            return """
            *Pulse Commit · 2026-05-14*

            ACTIVITY
              steps          12 483
              distance        8.42 km
              active         612 kcal
              rings          M 612/600 · E 38/30 · S 12/12

            HEART
              avg            71 bpm
              resting        58 bpm
              hrv            42 ms

            SLEEP
              total          7h 12m
              REM            1h 31m

            WORKOUTS
              running        38 min · 5.6 km
            """
        }
    }

    static func trimmedNonEmpty(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // Maps the current chat-id field to the value that must be written to
    // Keychain. An invalid non-empty entry clears the stored id (returns nil)
    // rather than leaving a stale prior value in place — otherwise the on-screen
    // field and the export target would silently disagree and health data could
    // keep flowing to a chat the user is no longer targeting.
    static func chatIdToPersist(for input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, ChatIdValidator.validate(trimmed).isSaveEnabled else {
            return nil
        }
        return trimmed
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        threadId = container.preferences.telegramThreadId.map(String.init) ?? ""
        let raw = container.preferences.telegramVerbosity
        verbosity = VerbosityOption(verbosity: SummaryVerbosity(rawValue: raw) ?? .standard)
        let secrets = container.secrets
        Task { @MainActor in
            botToken = (try? await secrets.get("tg_bot_token")) ?? nil ?? ""
            chatID = (try? await secrets.get("tg_chat_id")) ?? nil ?? ""
            persistedBotToken = Self.trimmedNonEmpty(for: botToken)
            persistedChatID = Self.trimmedNonEmpty(for: chatID)
            // Mark loaded AFTER setting fields so the onChange handlers don't
            // re-persist the freshly-loaded values during the assignment hop.
            loaded = true
            await refreshAutomaticWorkoutState()
        }
    }
}
