#if DEBUG
import Foundation
import HealthCore

enum MarketingDemo {
    static let launchArgument = "-marketingDemo"
    static let seededDayCount = 6
    static let steps = 12_483
    static let activeKcal = 642
    static let sleepMinutes = 451
    static let defaultsSuite = "app.pulsecommit.marketing-demo"

    static func isRequested(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(launchArgument)
    }

    @MainActor
    static func makeContainer(stepDelay: Duration = .milliseconds(900), now: Date = Date()) -> AppContainer {
        let defaults = UserDefaults(suiteName: defaultsSuite) ?? .standard
        defaults.removePersistentDomain(forName: defaultsSuite)
        let preferences = PreferencesStore(defaults: defaults)
        let registry = CategoryRegistry(categories: categories(delay: stepDelay))
        preferences.enabledCategoryIds = Set(registry.all.map(\.id))
        preferences.githubOwner = "octo-runner"
        preferences.githubRepo = "health-log"
        preferences.githubBranch = "main"
        preferences.githubExportEnabled = true
        preferences.telegramExportEnabled = true
        preferences.healthPermissionNoticeDismissed = true
        preferences.selectedPeriod = "today"
        for _ in 0..<10 { _ = preferences.recordSuccessfulManualExport() }

        let secrets = InMemorySecretsStore([
            KeychainTokenVault.storageKey: storedTokensJSON(),
            "tg_bot_token": "demo-bot",
            "tg_chat_id": "demo-chat"
        ])
        let history = (try? HistoryStore.inMemory()) ?? .noOp()
        seedHistory(history, now: now)
        let runGate = ExportRunGate()
        let healthStore = HealthStoreClient()

        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: history,
            healthStore: healthStore,
            registry: registry,
            orchestratorFactory: { container in
                Orchestrator(
                    windowResolver: ExportWindowResolver(timezone: .current),
                    pipeline: SnapshotPipeline(
                        registry: container.registry,
                        timezone: .current,
                        deviceName: "iPhone",
                        appVersion: "1.0.2"
                    ),
                    sinks: [
                        DemoSink(id: "github", delay: stepDelay * 3, reference: sha(seed: 0)),
                        DemoSink(id: "telegram", delay: stepDelay * 2, reference: "4182")
                    ],
                    historyStore: container.history,
                    runGate: runGate,
                    consentRequirements: [
                        "github": ConsentRequirement(
                            sinkID: "github",
                            destination: .github(owner: "octo-runner", repo: "health-log", branch: "main", subdir: "")
                        ),
                        "telegram": ConsentRequirement(
                            sinkID: "telegram",
                            destination: .telegram(chatID: "demo-chat", messageThreadID: nil)
                        )
                    ],
                    consentVerifier: { _, _ in true }
                )
            }
        )
        return container
    }

    static func sha(seed: Int) -> String {
        let base = "a4f03a9c1e7b52d8f6034bc19e2a7d5f80c3e61b"
        let shift = seed % base.count
        let index = base.index(base.startIndex, offsetBy: shift)
        return String(base[index...] + base[..<index])
    }

    private static func storedTokensJSON() -> String {
        let far = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
        let tokens = StoredTokens(accessToken: "demo", refreshToken: nil, accessExpiresAt: far, refreshExpiresAt: far)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(tokens)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @MainActor
    private static func seedHistory(_ history: HistoryStore, now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for offset in 1...seededDayCount {
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let started = calendar.date(byAdding: .minute, value: 21 * 60 + offset, to: day) ?? day
            try? history.append(HistoryEntry(
                startedAt: started,
                finishedAt: started.addingTimeInterval(4),
                status: .success,
                sinks: ["github", "telegram"],
                daysCovered: [formatter.string(from: day)],
                githubCommitSha: sha(seed: offset * 7),
                githubBranch: "main",
                telegramMessageReference: "\(4182 - offset)"
            ))
        }
    }

    private static func categories(delay: Duration) -> [any HealthCategory] {
        [
            DemoCategory(id: "steps", displayName: "Steps", delay: delay,
                         fragment: SummaryFragment(metrics: ["total": .int(steps)], unit: "count")),
            DemoCategory(id: "active_energy", displayName: "Active Energy", delay: delay,
                         fragment: SummaryFragment(metrics: ["total": .int(activeKcal)], unit: "kcal")),
            DemoCategory(id: "heart_rate", displayName: "Heart Rate", delay: delay,
                         fragment: SummaryFragment(metrics: ["avg": .int(68), "min": .int(51), "max": .int(164)], unit: "bpm")),
            DemoCategory(id: "hrv_sdnn", displayName: "Heart Rate Variability", delay: delay,
                         fragment: SummaryFragment(metrics: ["avg": .int(47)], unit: "ms")),
            DemoCategory(id: "sleep", displayName: "Sleep", delay: delay,
                         fragment: SummaryFragment(metrics: ["duration_minutes": .int(sleepMinutes)], unit: "min")),
            DemoCategory(id: "workouts", displayName: "Workouts", delay: delay,
                         fragment: SummaryFragment(metrics: ["count": .int(1)]))
        ]
    }
}

private struct DemoCategory: HealthCategory {
    let id: String
    let displayName: String
    let delay: Duration
    let fragment: SummaryFragment

    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        try await Task.sleep(for: delay)
        return [QuantitySampleDTO(
            categoryID: id,
            startDate: from,
            endDate: to,
            value: 1,
            unit: fragment.unit ?? "count",
            sourceName: "Demo",
            sourceBundleID: "app.pulsecommit.demo"
        )]
    }

    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        fragment
    }
}

private struct DemoSink: Sink {
    let id: String
    let delay: Duration
    let reference: String

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        try await Task.sleep(for: delay)
        return .success(reference: reference, url: nil)
    }
}
#endif
