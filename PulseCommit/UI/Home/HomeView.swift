import SwiftUI
import UIKit

struct HomeView: View {
    @Bindable var viewModel: HomeViewModel
    var livePreview: HomeLivePreviewModel?
    var deviceName: String
    var appVersion: String
    var timezoneAbbreviation: String
    var recentCommits: [RecentCommitRow] = []
    var recentCommitsBranchHint: String? = nil
    var healthPermissionRequestCompleted: Bool = false
    var healthPermissionNoticeDismissed: Bool = false
    var githubConfigured: Bool = false
    var telegramConfigured: Bool = false
    var webhookConfigured: Bool = false
    var onGrantHealth: () -> Void = {}
    var onOpenHealthSettings: () -> Void = {}
    var onDismissHealthPermissionNotice: () -> Void = {}
    var onConnectGitHub: () -> Void = {}
    var onConnectTelegram: () -> Void = {}
    var onReconnectGitHub: () -> Void = {}
    var onCustomRange: () -> Void = {}
    // Called when the user picks a new period from the chip-row Menu.
    // HomeContainerView persists this to PreferencesStore and updates the
    // viewModel.currentPeriod. The Menu does NOT dispatch an export.
    var onSelectPeriod: (HomeViewModel.Period) -> Void = { _ in }

    var isEmptyState: Bool {
        !githubConfigured && !telegramConfigured && !webhookConfigured
    }

    struct RecentCommitRow: Identifiable, Equatable {
        var id: UUID
        var shortSha: String?
        var dateLabel: String
        var timeAgo: String
        var summary: String
        var ok: Bool
    }

    var body: some View {
        ScrollView {
            if isEmptyState {
                VStack(alignment: .leading, spacing: 18) {
                    if viewModel.sessionExpired {
                        sessionExpiredBanner
                    }
                    emptyStateBody
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if shouldShowHealthPermissionNotice { healthPermissionNotice }
                    if viewModel.sessionExpired {
                        sessionExpiredBanner
                    }
                    bigButton
                    recentCommitsCard
                    liveStatsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .foregroundStyle(Theme.text)
    }

    private var emptyStateBody: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("$ pulse commit --init")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.accentSoft)
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 56, height: 56)
                Text("Welcome to Pulse Commit")
                    .font(.pcTitle)
                    .foregroundStyle(Theme.text)
                Text("Export Apple Health data to a Telegram chat or GitHub repo. Tokens stay in Keychain. Health data is sent only during an export; a Telegram setup test sends the sample message you approve.")
                    .font(.pcBody)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            setupStepsCard
            keychainFootnote
        }
    }

    private var setupStepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PCSectionHeader(title: "HEALTH PERMISSIONS")
            PCCard {
                setupRow(
                    index: 1,
                    title: healthPermissionRequestCompleted ? "Permission request completed" : "Request Health permissions",
                    subtitle: "Apple does not reveal which read categories you allowed",
                    done: healthPermissionRequestCompleted,
                    action: onGrantHealth
                )
            }
            if shouldShowHealthPermissionNotice { healthPermissionNotice }
            PCSectionHeader(title: "CHOOSE ONE DESTINATION")
            Text("Choose one destination to start. Telegram is recommended for a health chat; GitHub is an optional archive.")
                .font(.pcCaption)
                .foregroundStyle(Theme.muted)
            PCCard {
                VStack(spacing: 14) {
                    setupRow(
                        index: 2,
                        title: "Telegram · Recommended",
                        subtitle: "health chat · bot and chat ID",
                        done: telegramConfigured,
                        action: onConnectTelegram
                    )
                    Divider().overlay(Theme.divider)
                    setupRow(
                        index: 3,
                        title: "GitHub · Optional archive",
                        subtitle: "owner / repo · branch",
                        done: githubConfigured,
                        action: onConnectGitHub
                    )
                }
            }
        }
    }

    private var healthPermissionNotice: some View {
        PCCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Review read access")
                        .font(.pcBodySemibold)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Button(action: onDismissHealthPermissionNotice) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss read access notice")
                }
                Text("Apple Health does not tell apps which read categories you allowed. To review them, open the Health app → profile → Privacy → Apps. You can also open this app's Settings below.")
                    .font(.pcCaption)
                    .foregroundStyle(Theme.muted)
                Button("Open app Settings") { onOpenHealthSettings() }
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }
        }
    }

    private var shouldShowHealthPermissionNotice: Bool {
        healthPermissionRequestCompleted && !healthPermissionNoticeDismissed
    }

    private func setupRow(index: Int, title: String, subtitle: String, done: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", index))
                .font(.pcMonoDetail)
                .foregroundStyle(done ? Theme.success : Theme.dim)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.pcBody).foregroundStyle(Theme.text)
                Text(subtitle).font(.pcCaptionMono).foregroundStyle(Theme.dim)
            }
            Spacer()
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.success)
                    .frame(width: 28, height: 28)
            } else {
                Button(action: action) {
                    Text("Set up")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(
                            Capsule().stroke(Theme.accent, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var keychainFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("> tokens are stored in Apple Keychain")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
            Text("> no analytics · no servers · no telemetry")
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
        }
    }

    private var sessionExpiredBanner: some View {
        Button(action: onReconnectGitHub) {
            PCCard {
                HStack(spacing: 12) {
                    PCStatusDot(color: Theme.warn, pulsing: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub session expired")
                            .font(.pcBody)
                            .foregroundStyle(Theme.text)
                        Text("> tap to reconnect")
                            .font(.pcCaptionMono)
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Text("Reconnect")
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    static func headerPillText(for phase: HomeViewModel.Phase) -> String {
        switch phase {
        case .running: return "RUNNING"
        case .error: return "FAILED"
        case .idle, .done: return "READY"
        }
    }

    static func headerPillIsError(for phase: HomeViewModel.Phase) -> Bool {
        if case .error = phase { return true }
        return false
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                PCPill(
                    text: "● \(Self.headerPillText(for: viewModel.phase))",
                    monospaced: true,
                    foreground: Self.headerPillIsError(for: viewModel.phase) ? Theme.error : Theme.accent,
                    background: Self.headerPillIsError(for: viewModel.phase) ? Theme.elevated : Theme.accentSoft
                )
                Text("Pulse Commit")
                    .font(.pcLargeTitle)
                    .foregroundStyle(Theme.text)
                Text(Self.buildIdentitySupertitle(
                    appVersion: appVersion,
                    deviceName: deviceName,
                    timezoneAbbreviation: timezoneAbbreviation
                ))
                    .font(.pcCaptionMono)
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.muted)
                .padding(.top, 28)
        }
    }

    private func dispatch(_ mode: ExportRequest.Mode?) {
        Task { await viewModel.runExport(sinkOverride: nil, modeOverride: mode) }
    }

    // Every phase renders the same slots (two-line sub-label, stage line,
    // progress bar) and only toggles their opacity, so the natural height is
    // phase-independent; this floor only guards against a shorter future layout.
    static let bigButtonMinHeight: CGFloat = 232

    // ─────────────────────────────────────────────────────────────────────
    // BIG BUTTON — two-zone composition:
    //   • TOP  zone (heroBigButtonZone): tap dispatches export with the
    //     currently-selected period.
    //   • DIVIDER: dashed horizontal hairline separating zones (ui-ux-pro-max).
    //   • BOTTOM zone (bigButtonChipRow): tap opens the period Menu. Selection
    //     updates `viewModel.currentPeriod` via `onSelectPeriod` but does NOT
    //     dispatch an export.
    // Both zones share the lime background, rounded shape, and accent glow.
    // ─────────────────────────────────────────────────────────────────────
    static let bigButtonCoordinateSpace = "home.bigButton"

    var bigButton: some View {
        VStack(alignment: .leading, spacing: 0) {
            topZone
            dashedDivider
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: BigButtonDividerMinYKey.self,
                            value: geo.frame(in: .named(Self.bigButtonCoordinateSpace)).minY
                        )
                    }
                )
            bigButtonChipRow
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: Self.bigButtonMinHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(buttonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
        // pc-hil: accent-glow per CLAUDE.md (atmospheric, symmetric, no offset),
        // not a directional card shadow. Theme.accentSoft is already the lime
        // accent at 0.16 alpha — perfect for a 24pt diffuse halo around the
        // big button. Drop shadows on cards are forbidden by the design spec;
        // only the home Export button gets a glow.
        .shadow(color: Theme.accentSoft, radius: 24, x: 0, y: 0)
        .coordinateSpace(.named(Self.bigButtonCoordinateSpace))
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
    }

    private var isRunning: Bool {
        if case .running = viewModel.phase { return true }
        return false
    }

    private var topZone: some View {
        // Wrap the press-target in a real Button so VoiceOver activate,
        // Voice Control ("tap Export"), Stage Manager keyboard Return, and
        // Switch Control all reach the same dispatch path that touch does.
        // The custom HeroPressStyle exposes configuration.isPressed for the
        // press-down scale effect previously bound to a @State flag.
        // Haptic feedback rides on viewModel.phase transitions via
        // .sensoryFeedback (replacing the imperative UIImpactFeedbackGenerator),
        // so the medium-impact tap is felt the moment the orchestrator flips
        // to .running.
        Button {
            guard viewModel.phase != .running else { return }
            dispatch(nil)
        } label: {
            topZoneContent
        }
        .buttonStyle(HeroPressStyle())
        .disabled(isRunning)
        .accessibilityLabel(Text(buttonTitle))
        .accessibilityHint(Text(Self.accessibilityHintText(for: viewModel, buttonSubLabel: buttonSubLabel)))
        .accessibilityIdentifier("home.bigButton.topZone")
        .sensoryFeedback(.impact(weight: .medium), trigger: viewModel.phase) { old, new in
            // Fire only on the user-initiated idle→running transition. Skip
            // running→done/error so we don't double-tap the user after they
            // already felt the activation haptic.
            if case .idle = old, case .running = new { return true }
            if case .error = old, case .running = new { return true }
            return false
        }
    }

    private var topZoneContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(supertitle)
                    .font(.pcCaptionMono)
                    .foregroundStyle(Color.black.opacity(0.55))
                Spacer()
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .opacity(isRunning ? 0 : 1)
                    PCStatusDot(color: Color.black, pulsing: isRunning)
                        .opacity(isRunning ? 1 : 0)
                        .accessibilityHidden(!isRunning)
                }
            }
            Text(buttonTitle)
                .font(.pcBigButton)
                .foregroundStyle(Color.black)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(buttonSubLabel ?? " ")
                .font(.pcMonoDetail)
                .foregroundStyle(Color.black.opacity(0.65))
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .opacity(buttonSubLabel == nil ? 0 : 1)
                .accessibilityHidden(buttonSubLabel == nil)
            VStack(alignment: .leading, spacing: 14) {
                stageLine
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.black.opacity(0.15)).frame(height: 3)
                        Capsule().fill(Color.black).frame(width: geo.size.width * 0.4, height: 3)
                    }
                }
                .frame(height: 3)
                .accessibilityHidden(true)
            }
            .opacity(isRunning ? 1 : 0)
            .accessibilityHidden(!isRunning)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.bottom, 14)
        .animation(.easeInOut(duration: 0.18), value: viewModel.stageLabel)
        .contentShape(Rectangle())
    }

    private var stageLine: some View {
        Text(" ")
            .font(.pcCaptionMono)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) { stageText }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(viewModel.currentStage))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var stageText: some View {
        HStack(spacing: 0) {
            Text(viewModel.stagePrefix)
                .font(.pcCaptionMono)
                .foregroundStyle(Color.black.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
            if let label = viewModel.stageLabel {
                Text(label)
                    .font(.pcCaptionMono)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .transition(.opacity)
                    .id(label)
            }
            if let counter = viewModel.stageCounter {
                Text(" \(counter)")
                    .font(.pcCaptionMono)
                    .foregroundStyle(Color.black.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // Dashed hairline implemented with StrokeStyle to honour ui-ux-pro-max's
    // dashed-divider token. Drawn at 0.5 opacity on black so it reads on
    // the lime background without overpowering it.
    private var dashedDivider: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0.5))
                path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
            }
            .stroke(
                Color.black.opacity(0.35),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
        .frame(height: 1)
    }

    // Bottom-zone chip row: inline period selector embedded inside the big
    // button. Tap opens a Menu anchored to the row (not the whole button),
    // fixing the action-sheet anchoring complaint. The whole row is the
    // Menu trigger so the chevron is the visual affordance.
    private var bigButtonChipRow: some View {
        Menu {
            periodMenuContent
        } label: {
            HStack(spacing: 0) {
                chip(for: .today, label: "today")
                chipSeparator
                chip(for: .yesterday, label: "yesterday")
                chipSeparator
                chip(for: .last7Days, label: "7d")
                chipSeparator
                chip(for: .last30Days, label: "30d")
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.bigButton.chipRow")
    }

    private func chip(for period: HomeViewModel.Period, label: String) -> some View {
        let selected = viewModel.currentPeriod == period
        return Text(label)
            .font(.pcCaptionMono)
            .fontWeight(selected ? .bold : .regular)
            .foregroundStyle(selected ? Color.black : Color.black.opacity(0.5))
            .underline(selected, color: Color.black)
    }

    private var chipSeparator: some View {
        Text("·")
            .font(.pcCaptionMono)
            .foregroundStyle(Color.black.opacity(0.35))
            .padding(.horizontal, 8)
    }

    // Menu content for the chip row. Uses a Picker bound to `currentPeriod`
    // so SwiftUI draws checkmarks next to the selected row automatically.
    @ViewBuilder
    private var periodMenuContent: some View {
        Picker("Period", selection: Binding(
            get: { viewModel.currentPeriod },
            set: { newValue in onSelectPeriod(newValue) }
        )) {
            Text("Today").tag(HomeViewModel.Period.today)
            Text("Yesterday").tag(HomeViewModel.Period.yesterday)
            Text("Last 7 days").tag(HomeViewModel.Period.last7Days)
            Text("Last 30 days").tag(HomeViewModel.Period.last30Days)
        }
        .pickerStyle(.inline)
    }

    private var period: HomeViewModel.Period {
        viewModel.currentPeriod
    }

    private var stepCountForSubLabel: Int? {
        guard let livePreview else { return nil }
        switch period {
        case .today: return livePreview.todaySteps
        case .yesterday: return livePreview.yesterdaySteps
        default: return nil
        }
    }

    private var supertitle: String {
        switch viewModel.phase {
        case .running: return "$ pulse commit --in-progress"
        case .error: return "$ pulse commit --retry"
        default:
            switch period {
            case .today: return "$ pulse commit --since=today"
            case .yesterday: return "$ pulse commit --since=yesterday"
            case .last7Days: return "$ pulse commit --since=7d"
            case .last30Days: return "$ pulse commit --since=30d"
            case .custom: return "$ pulse commit --range=custom"
            }
        }
    }

    private var buttonTitle: String {
        switch viewModel.phase {
        case .running: return "Committing…"
        case .error: return "Retry Export"
        default: return "Export Now"
        }
    }

    static func computeButtonSubLabel(for viewModel: HomeViewModel, periodSubLabel: String) -> String? {
        switch viewModel.phase {
        case .idle:
            return periodSubLabel
        case .running:
            return nil
        case .done(let at):
            return "Last commit · \(Self.relativeTime(from: at)) · ✓"
        case .error(let reason):
            return "Last attempt failed · \(reason)"
        }
    }

    static func accessibilityHintText(for viewModel: HomeViewModel, buttonSubLabel: String?) -> String {
        // During .running we keep the hint static — the live stage text is
        // surfaced via a separate accessibility element on the HStack with
        // .updatesFrequently trait so VoiceOver doesn't spam users with ~28
        // hint announcements during a long export.
        if case .running = viewModel.phase {
            return "Export in progress"
        }
        return buttonSubLabel ?? ""
    }

    private var buttonSubLabel: String? {
        Self.computeButtonSubLabel(for: viewModel, periodSubLabel: periodSubLabel)
    }

    private var periodSubLabel: String {
        let stepsSuffix: String
        if let count = stepCountForSubLabel {
            stepsSuffix = " · \(HomeLivePreviewModel.formatSteps(count)) steps"
        } else {
            stepsSuffix = ""
        }
        switch period {
        case .today:
            return "Today · since 00:00\(stepsSuffix) · ready to commit"
        case .yesterday:
            return "Yesterday · final\(stepsSuffix) · ready to commit"
        case .last7Days:
            return "Last 7 days · ready to commit"
        case .last30Days:
            return "Last 30 days · ready to commit"
        case .custom:
            // Unreachable: no UI path sets .custom and storage restores it
            // to .today; keeps the switch total until a date-picker ships.
            return "Today · since 00:00\(stepsSuffix) · ready to commit"
        }
    }

    static func buildIdentitySupertitle(
        appVersion: String,
        deviceName: String,
        timezoneAbbreviation: String,
        gitSHA: String = BuildIdentity.gitSHA,
        commitDate: String = BuildIdentity.commitDate
    ) -> String {
        "$ v\(appVersion) · \(gitSHA) · \(commitDate) · \(deviceName) · \(timezoneAbbreviation)"
    }

    private static func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var buttonBackground: Color {
        if case .error = viewModel.phase {
            return Theme.error
        }
        return Theme.accent
    }

    var recentCommitsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PCSectionHeader(title: "RECENT COMMITS", hint: recentCommitsBranchHint)
            PCCard {
                if recentCommits.isEmpty {
                    HStack {
                        Text("No exports yet · tap Export Now")
                            .font(.pcBody)
                            .foregroundStyle(Theme.muted)
                        Spacer()
                    }
                    .frame(minHeight: 60)
                    .accessibilityIdentifier("home.recentCommits.empty")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(recentCommits.enumerated()), id: \.element.id) { index, row in
                            recentCommitRow(
                                row,
                                isFirst: index == 0,
                                isLast: index == recentCommits.count - 1
                            )
                            if index < recentCommits.count - 1 {
                                Divider().overlay(Theme.divider)
                            }
                        }
                    }
                    .accessibilityIdentifier("home.recentCommits.list")
                }
            }
        }
    }

    private func recentCommitRow(_ row: RecentCommitRow, isFirst: Bool, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            commitNode(ok: row.ok, isFirst: isFirst, isLast: isLast)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.shortSha ?? "———————")
                        .font(.pcMonoDetail)
                        .fontWeight(.semibold)
                        .foregroundStyle(row.ok ? Theme.text : Theme.error)
                    Text(row.dateLabel)
                        .font(.pcCaptionMono)
                        .foregroundStyle(Theme.dim)
                }
                Text(row.summary)
                    .font(.pcCaptionMono)
                    .foregroundStyle(row.ok ? Theme.muted : Theme.error)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Text(row.timeAgo)
                .font(.pcCaptionMono)
                .foregroundStyle(Theme.dim)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .accessibilityIdentifier("home.recentCommits.row")
    }

    // Commit node: a 2pt vertical connector behind the `commit` template
    // asset glyph (custom — no SF Symbol equivalent), sized 16pt and tinted
    // success/error. The connector is hidden on the first half above the top
    // row and the bottom half below the last row via conditional inclusion.
    private func commitNode(ok: Bool, isFirst: Bool, isLast: Bool) -> some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let centerY = geo.size.height / 2
            ZStack {
                if !isFirst {
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(width: 2, height: centerY)
                        .position(x: centerX, y: centerY / 2)
                }
                if !isLast {
                    Rectangle()
                        .fill(Theme.divider)
                        .frame(width: 2, height: centerY)
                        .position(x: centerX, y: centerY + centerY / 2)
                }
                Image("commit")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(ok ? Theme.success : Theme.error)
                    .position(x: centerX, y: centerY)
            }
        }
    }

    // The live-preview tile section can only render today/yesterday windows
    // — multi-day periods (7d, 30d, custom) reuse the today window as a
    // best-effort preview surface; the actual export still respects the
    // selected period via the big-button dispatch path.
    private var isTodayPreview: Bool {
        period == .yesterday ? false : true
    }

    private var tileSectionTitle: String {
        switch period {
        case .yesterday: return "TO BE EXPORTED · YESTERDAY"
        case .last7Days: return "TO BE EXPORTED · LAST 7 DAYS"
        case .last30Days: return "TO BE EXPORTED · LAST 30 DAYS"
        case .custom: return "TO BE EXPORTED · CUSTOM"
        case .today: return "TO BE EXPORTED · TODAY"
        }
    }

    private var tileSectionHint: String {
        switch period {
        case .yesterday: return "FINAL"
        case .today: return "LIVE"
        default: return "PREVIEW"
        }
    }

    private var tileSteps: Int? {
        isTodayPreview ? livePreview?.todaySteps : livePreview?.yesterdaySteps
    }
    private var tileWorkouts: Int? {
        isTodayPreview ? livePreview?.todayWorkoutCount : livePreview?.yesterdayWorkoutCount
    }
    private var tileSleep: Int? {
        isTodayPreview ? livePreview?.todaySleepMinutes : livePreview?.yesterdaySleepMinutes
    }
    private var tileKcal: Double? {
        isTodayPreview ? livePreview?.todayActiveKcal : livePreview?.yesterdayActiveKcal
    }

    private var livePreviewWindow: HomeLivePreviewModel.Window {
        isTodayPreview ? .today : .yesterday
    }

    private var liveStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PCSectionHeader(title: tileSectionTitle, hint: tileSectionHint)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                statTile(label: "steps", value: HomeLivePreviewModel.formatSteps(tileSteps))
                statTile(label: "workouts", value: HomeLivePreviewModel.formatWorkouts(tileWorkouts))
                statTile(label: "sleep", value: HomeLivePreviewModel.formatSleep(tileSleep))
                statTile(label: "kcal", value: HomeLivePreviewModel.formatKcal(tileKcal))
            }
            .task(id: livePreviewTaskId) {
                await livePreview?.refresh(mode: livePreviewWindow)
            }
            // Smart-mode noon-boundary refresh removed — period is user-set
            // and persisted, not time-driven. We still refresh the live
            // preview when the app returns to the foreground.
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await livePreview?.refresh(mode: livePreviewWindow) }
            }
        }
    }

    private var livePreviewTaskId: String {
        let m: String
        switch period {
        case .today: m = "t"
        case .yesterday: m = "y"
        case .last7Days: m = "7"
        case .last30Days: m = "30"
        case .custom: m = "c"
        }
        return livePreview == nil ? "none-\(m)" : "live-\(m)"
    }

    // Hero-number box height: matches the `pcHeroNumber` font's natural line
    // box (size 64 monospaced → ~76pt line height). Locking the value Text
    // into this height keeps all four stat tiles visually equal even when
    // `.minimumScaleFactor(0.5)` shrinks long values like "46 592" to fit on
    // one line — without the floor, a scaled-down number renders shorter and
    // its tile collapses, producing the uneven 2x2 grid.
    static let statTileHeroHeight: CGFloat = 76

    private func statTile(label: String, value: String) -> some View {
        PCCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(label.uppercased())
                    .font(.pcLabel)
                    .tracking(1.5)
                    .foregroundStyle(Theme.dim)
                Text(value)
                    // Fixed 36pt monospaced instead of pcHeroNumber + minimumScaleFactor.
                    // Long values like "46 592" used to scale down to fit while short
                    // values like "3" stayed at full pcHeroNumber size — producing
                    // visually inconsistent font sizes across the grid. A flat 36pt
                    // fits the widest plausible value (6-char step count with thin-
                    // space grouping) at iPhone half-tile width without scaling.
                    // SF Mono per CLAUDE.md typography rule: every numeric value uses mono.
                    .font(.pcStatTile)
                    .foregroundStyle(Theme.text)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Self.statTileHeroHeight, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// pc-h79: a ButtonStyle that mirrors the previous gesture-driven press
// animation (0.98 scale, 80ms ease-out) while preserving the system Button
// activation paths (VoiceOver, Voice Control, Stage Manager keyboard, Switch
// Control) that onTapGesture silently skips. No background — the surrounding
// big-button card draws its own lime fill and stroke.
struct HeroPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct BigButtonDividerMinYKey: PreferenceKey {
    static let defaultValue: CGFloat = -1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
