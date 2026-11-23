import HealthCore
import XCTest
@testable import PulseCommit

@MainActor
final class CoverageFailureCallerTests: XCTestCase {
    func test_homeKeepsCurrentCoverageGuidanceWhenHistoryIsNoOp() async throws {
        for error in [HealthHistoryCoverageError.limitedHistory, .checkFailed] {
            let harness = try await makeHarness(history: .noOp(), coverageError: error)
            let viewModel = HomeViewModel(container: harness.container)

            await viewModel.runExport()

            XCTAssertEqual(viewModel.phase, .error(reason: error.userMessage))
            let sinkCalls = await harness.sink.callCount
            XCTAssertEqual(sinkCalls, 0)
            XCTAssertTrue(try harness.container.history.recentEntries(limit: 1).isEmpty)
        }
    }

    func test_intentKeepsCurrentCoverageGuidanceWhenHistoryIsNoOp() async throws {
        for error in [HealthHistoryCoverageError.limitedHistory, .checkFailed] {
            let harness = try await makeHarness(history: .noOp(), coverageError: error)

            do {
                _ = try await IntentRunner.run(mode: .lastDayOnly, container: harness.container)
                XCTFail("expected a typed coverage error")
            } catch let intentError as IntentError {
                assert(intentError, represents: error)
            }

            let sinkCalls = await harness.sink.callCount
            XCTAssertEqual(sinkCalls, 0)
            XCTAssertNil(try harness.container.history.cursor())
        }
    }

    func test_intentUsesCurrentDirectFailureInsteadOfNewerStaleHistory() async throws {
        let history = try HistoryStore.inMemory()
        try history.append(HistoryEntry(
            startedAt: .distantFuture,
            finishedAt: .distantFuture,
            status: .failed,
            sinks: ["telegram"],
            daysCovered: [],
            errorMessage: HealthHistoryCoverageError.limitedHistory.userMessage,
            errorKind: HistoryErrorKind.limitedHealthHistory
        ))
        let harness = try await makeHarness(history: history, coverageError: .checkFailed)

        do {
            _ = try await IntentRunner.run(mode: .lastDayOnly, container: harness.container)
            XCTFail("expected healthHistoryCheckFailed")
        } catch let intentError as IntentError {
            assert(intentError, represents: .checkFailed)
        }
    }

    private func assert(
        _ intentError: IntentError,
        represents coverageError: HealthHistoryCoverageError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let reason: String
        switch (intentError, coverageError) {
        case (.limitedHealthHistory(let message), .limitedHistory),
             (.healthHistoryCheckFailed(let message), .checkFailed):
            reason = message
        default:
            return XCTFail("wrong Intent error: \(intentError)", file: file, line: line)
        }
        XCTAssertEqual(reason, coverageError.userMessage, file: file, line: line)
        XCTAssertTrue(reason.contains("range"), file: file, line: line)
        XCTAssertTrue(reason.contains("Full History"), file: file, line: line)
        XCTAssertTrue(reason.contains("disable affected optional categories"), file: file, line: line)
    }

    private func makeHarness(
        history: HistoryStore,
        coverageError: HealthHistoryCoverageError
    ) async throws -> CoverageCallerHarness {
        let secrets = InMemorySecretsStore()
        try await secrets.set("bot", for: "tg_bot_token")
        try await secrets.set("chat", for: "tg_chat_id")
        let defaults = UserDefaults(suiteName: "CoverageFailureCallerTests.\(UUID().uuidString)")!
        let preferences = PreferencesStore(defaults: defaults)
        preferences.enabledCategoryIds = ["steps"]
        preferences.githubExportEnabled = false
        preferences.telegramExportEnabled = true
        let healthStore = HealthStoreClient()
        let registry = DefaultRegistryFactory.make(store: healthStore)
        let sink = CoverageCallerSink()
        let requirement = ConsentRequirement(
            sinkID: "telegram",
            destination: .telegram(chatID: "chat", messageThreadID: nil)
        )
        let factory: @MainActor (AppContainer) async -> Orchestrator = { container in
            let timezone = TimeZone(identifier: "UTC")!
            return Orchestrator(
                windowResolver: ExportWindowResolver(timezone: timezone),
                pipeline: SnapshotPipeline(
                    registry: container.registry,
                    timezone: timezone,
                    deviceName: "Test",
                    appVersion: "1.0"
                ),
                sinks: [sink],
                historyStore: container.history,
                consentRequirements: ["telegram": requirement],
                consentVerifier: { _, _ in true },
                historyValidator: { _, _, _ in throw coverageError }
            )
        }
        let container = AppContainer(
            secrets: secrets,
            preferences: preferences,
            history: history,
            healthStore: healthStore,
            registry: registry,
            orchestratorFactory: factory
        )
        return CoverageCallerHarness(container: container, sink: sink)
    }
}

private struct CoverageCallerHarness {
    let container: AppContainer
    let sink: CoverageCallerSink
}

private actor CoverageCallerSink: Sink {
    nonisolated let id = "telegram"
    private(set) var callCount = 0

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        callCount += 1
        return .success(reference: "unexpected", url: nil)
    }
}
