import XCTest
@testable import PulseCommit

@MainActor
final class HomeViewModelTests: XCTestCase {
    private static var githubScope: HealthExportConsentScope {
        HealthExportConsentScope(
            destination: .github(owner: "octocat", repo: "health", branch: "main", subdir: ""),
            enabledCategoryIds: ["steps"]
        )
    }

    @MainActor
    static func makeViewModel(phase: HomeViewModel.Phase = .idle) -> HomeViewModel {
        let viewModel = HomeViewModel(
            runRequest: { _, _ in .success },
            enabledCategoryIds: { [] },
            enabledSinkIds: { [] },
            recentHistory: { [] },
            clock: { Date(timeIntervalSince1970: 1_700_000_000) },
            calendar: .current,
            initialPeriod: .today
        )
        viewModel.phase = phase
        return viewModel
    }

    func test_runExport_success_transitionsIdleRunningDone() async {
        let calls = AsyncStream.makeStream(of: HistoryEntry.Status.self)
        let observed = ObservedPhases()
        let viewModel = HomeViewModel(
            runRequest: { _, _ in
                observed.append(.running)
                return .success
            },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] }
        )
        _ = calls

        XCTAssertEqual(viewModel.phase, .idle)
        await viewModel.runExport()
        if case .done = viewModel.phase {} else {
            XCTFail("expected .done, got \(viewModel.phase)")
        }
    }

    func test_missingConsentPresentsDisclosureWithoutRunning() async {
        var runCount = 0
        let viewModel = HomeViewModel(
            runRequest: { _, _ in runCount += 1; return .success },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] },
            consentPreflight: { _ in [Self.githubScope] }
        )

        await viewModel.runExport()

        XCTAssertEqual(viewModel.pendingConsentScope, Self.githubScope)
        XCTAssertEqual(runCount, 0)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func test_acceptRecordsConsentBeforeRun() async {
        var accepted = false
        var runObservedAcceptance = false
        let viewModel = HomeViewModel(
            runRequest: { _, _ in runObservedAcceptance = accepted; return .success },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] },
            consentPreflight: { _ in accepted ? [] : [Self.githubScope] },
            acceptConsent: { _ in accepted = true; return true }
        )

        await viewModel.runExport()
        await viewModel.allowPendingConsent()

        XCTAssertTrue(runObservedAcceptance)
        if case .done = viewModel.phase {} else { XCTFail("expected done") }
    }

    func test_declineDoesNotRun() async {
        var runCount = 0
        let viewModel = HomeViewModel(
            runRequest: { _, _ in runCount += 1; return .success },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] },
            consentPreflight: { _ in [Self.githubScope] }
        )

        await viewModel.runExport()
        viewModel.declinePendingConsent()

        XCTAssertEqual(runCount, 0)
        XCTAssertNil(viewModel.pendingConsentScope)
    }

    func test_changedTargetWhileSheetOpenRegeneratesDisclosure() async {
        let telegram = HealthExportConsentScope(
            destination: .telegram(chatID: "-100999", messageThreadID: nil),
            enabledCategoryIds: ["steps"]
        )
        var current = Self.githubScope
        let viewModel = HomeViewModel(
            runRequest: { _, _ in XCTFail("must remain gated"); return .failed },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] },
            consentPreflight: { _ in [current] },
            acceptConsent: { _ in false }
        )

        await viewModel.runExport()
        current = telegram
        await viewModel.allowPendingConsent()

        XCTAssertEqual(viewModel.pendingConsentScope, telegram)
    }

    func test_runExport_failure_transitionsToError() async {
        let viewModel = HomeViewModel(
            runRequest: { _, _ in .failed },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { [] }
        )
        await viewModel.runExport()
        if case .error = viewModel.phase {} else {
            XCTFail("expected .error, got \(viewModel.phase)")
        }
    }

    func test_runExport_directLimitedHistoryIgnoresStaleHistory() async {
        let message = HealthHistoryCoverageError.limitedHistory.userMessage
        let history = [HomeHistorySnapshot(
            status: .failed,
            errorMessage: HealthHistoryCoverageError.checkFailed.userMessage,
            errorKind: HistoryErrorKind.healthHistoryCheckFailed
        )]
        let viewModel = HomeViewModel(
            runRequest: { _, _ in
                Orchestrator.RunResult(status: .failed, coverageError: .limitedHistory)
            },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] },
            recentHistory: { history }
        )

        await viewModel.runExport()

        XCTAssertEqual(viewModel.phase, .error(reason: message))
        XCTAssertTrue(message.contains("range"))
        XCTAssertTrue(message.contains("Full History"))
        XCTAssertTrue(message.contains("disable affected optional categories"))
    }

    func test_runExport_failureKeepsRecordedEntryIdInErrorPhase() async {
        let id = UUID()
        let viewModel = HomeViewModel(
            runRequest: { _, _ in Orchestrator.RunResult(status: .failed, entryId: id) },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] }
        )
        await viewModel.runExport()
        XCTAssertEqual(viewModel.phase, .error(reason: "export failed", entryId: id))
    }

    func test_runExport_legacyPaywalledStatusIsTreatedAsFailure() async {
        let viewModel = HomeViewModel(
            runRequest: { _, _ in Orchestrator.RunResult(status: .paywalled) },
            enabledCategoryIds: { ["steps"] },
            enabledSinkIds: { ["github"] }
        )
        await viewModel.runExport()
        XCTAssertEqual(viewModel.phase, .error(reason: "export failed"))
    }

    func test_runExport_buildsSmartRequestWithProvidedIds() async {
        var captured: ExportRequest?
        // Force PM clock so smart mode resolves to .todayLive.
        let pm = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 14))!
        let viewModel = HomeViewModel(
            runRequest: { request, _ in
                captured = request
                return .success
            },
            enabledCategoryIds: { ["steps", "sleep"] },
            enabledSinkIds: { ["github", "telegram"] },
            clock: { pm }
        )
        await viewModel.runExport()
        XCTAssertEqual(captured?.mode, .todayLive)
        XCTAssertEqual(captured?.enabledCategoryIds, ["steps", "sleep"])
        XCTAssertEqual(captured?.enabledSinkIds, ["github", "telegram"])
    }

    func test_sessionExpired_trueAfterFailedRunWithSessionExpiredError() async {
        var history: [HomeHistorySnapshot] = []
        let viewModel = HomeViewModel(
            runRequest: { _, _ in
                history.insert(
                    HomeHistorySnapshot(
                        status: .failed,
                        errorMessage: "sink failed: Your GitHub session expired. Reconnect to continue.",
                        errorKind: HistoryErrorKind.sessionExpired
                    ),
                    at: 0
                )
                return .failed
            },
            enabledCategoryIds: { [] },
            enabledSinkIds: { ["github"] },
            recentHistory: { history }
        )
        XCTAssertFalse(viewModel.sessionExpired)
        await viewModel.runExport()
        XCTAssertTrue(viewModel.sessionExpired)
    }

    func test_sessionExpired_falseAfterSubsequentSuccess() async {
        var history: [HomeHistorySnapshot] = [
            HomeHistorySnapshot(
                status: .failed,
                errorMessage: "sink failed: ...",
                errorKind: HistoryErrorKind.sessionExpired
            )
        ]
        let viewModel = HomeViewModel(
            runRequest: { _, _ in
                history.insert(
                    HomeHistorySnapshot(status: .success, errorMessage: nil, errorKind: nil),
                    at: 0
                )
                return .success
            },
            enabledCategoryIds: { [] },
            enabledSinkIds: { ["github"] },
            recentHistory: { history }
        )
        viewModel.refreshSessionExpired()
        XCTAssertTrue(viewModel.sessionExpired)
        await viewModel.runExport()
        XCTAssertFalse(viewModel.sessionExpired)
    }

    func test_sessionExpired_ignoresOlderSessionExpiredAfterRecentSuccess() {
        let history: [HomeHistorySnapshot] = [
            HomeHistorySnapshot(status: .success, errorMessage: nil, errorKind: nil),
            HomeHistorySnapshot(
                status: .failed,
                errorMessage: "sink failed: ...",
                errorKind: HistoryErrorKind.sessionExpired
            )
        ]
        let viewModel = HomeViewModel(
            runRequest: { _, _ in .success },
            enabledCategoryIds: { [] },
            enabledSinkIds: { [] },
            recentHistory: { history }
        )
        viewModel.refreshSessionExpired()
        XCTAssertFalse(viewModel.sessionExpired)
    }

    /// Regression: HomeViewModel must NOT classify a failed entry as session-expired
    /// just because the human-readable error text happens to contain "sessionExpired".
    /// Detection is structured via `errorKind`, not substring matching. This is the
    /// W2-tandem guarantee that lets pc-007 (LocalizedError) ship safely.
    func test_sessionExpired_ignoresSubstringMatchOnErrorMessage() {
        let history: [HomeHistorySnapshot] = [
            HomeHistorySnapshot(
                status: .failed,
                errorMessage: "some other failure mentioning sessionExpired in text",
                errorKind: nil
            )
        ]
        let viewModel = HomeViewModel(
            runRequest: { _, _ in .failed },
            enabledCategoryIds: { [] },
            enabledSinkIds: { ["github"] },
            recentHistory: { history }
        )
        viewModel.refreshSessionExpired()
        XCTAssertFalse(viewModel.sessionExpired)
    }

    func test_runExport_whileRunning_isIgnored() async {
        var callCount = 0
        let viewModel = HomeViewModel(
            runRequest: { _, _ in
                callCount += 1
                try? await Task.sleep(nanoseconds: 50_000_000)
                return .success
            },
            enabledCategoryIds: { [] },
            enabledSinkIds: { [] }
        )
        async let first: Void = viewModel.runExport()
        // give the first call a chance to flip to .running
        try? await Task.sleep(nanoseconds: 10_000_000)
        await viewModel.runExport()
        await first
        XCTAssertEqual(callCount, 1)
    }

    @MainActor
    func test_friendlyName_mapsKnownCategoryIds() {
        let viewModel = HomeViewModelTests.makeViewModel()
        XCTAssertEqual(viewModel.friendlyName(for: "steps"), "steps")
        XCTAssertEqual(viewModel.friendlyName(for: "heart_rate"), "heart rate")
        XCTAssertEqual(viewModel.friendlyName(for: "hrv_sdnn"), "HRV")
        XCTAssertEqual(viewModel.friendlyName(for: "vo2_max"), "VO2 max")
        XCTAssertEqual(viewModel.friendlyName(for: "workouts"), "workouts")
        XCTAssertEqual(viewModel.friendlyName(for: "active_energy"), "active energy")
    }

    @MainActor
    func test_friendlyName_unknownIdReturnsItselfVerbatim() {
        let viewModel = HomeViewModelTests.makeViewModel()
        XCTAssertEqual(viewModel.friendlyName(for: "unknown_id_xyz"), "unknown_id_xyz")
    }

    @MainActor
    func test_currentStage_isComputedFromSplitFields() {
        let viewModel = HomeViewModelTests.makeViewModel()
        viewModel.stagePrefix = "> totals · "
        viewModel.stageLabel = "steps"
        viewModel.stageCounter = "(3/14)"
        XCTAssertEqual(viewModel.currentStage, "> totals · steps (3/14)")
    }

    @MainActor
    func test_currentStage_omitsNilLabelAndCounter() {
        let viewModel = HomeViewModelTests.makeViewModel()
        viewModel.stagePrefix = "> starting export…"
        viewModel.stageLabel = nil
        viewModel.stageCounter = nil
        XCTAssertEqual(viewModel.currentStage, "> starting export…")
    }

    @MainActor
    func test_currentStage_isEmptyStringWhenAllFieldsAreEmpty() {
        let viewModel = HomeViewModelTests.makeViewModel()
        viewModel.stagePrefix = ""
        viewModel.stageLabel = nil
        viewModel.stageCounter = nil
        XCTAssertEqual(viewModel.currentStage, "")
    }

    @MainActor
    func test_updateStage_fetching() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.fetching(day: 0, totalDays: 0))
        XCTAssertEqual(vm.currentStage, "> starting export…")
    }

    @MainActor
    func test_updateStage_readingSummary_multi() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.readingSummary(categoryID: "steps", completed: 3, total: 14))
        XCTAssertEqual(vm.stagePrefix, "> totals · ")
        XCTAssertEqual(vm.stageLabel, "steps")
        XCTAssertEqual(vm.stageCounter, "(3/14)")
        XCTAssertEqual(vm.currentStage, "> totals · steps (3/14)")
    }

    @MainActor
    func test_updateStage_readingSummary_singleCategory() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.readingSummary(categoryID: "steps", completed: 1, total: 1))
        XCTAssertEqual(vm.stagePrefix, "> totals · ")
        XCTAssertEqual(vm.stageLabel, "steps")
        XCTAssertNil(vm.stageCounter)
        XCTAssertEqual(vm.currentStage, "> totals · steps")
    }

    @MainActor
    func test_updateStage_startingSamplesFetch_clearsPriorReadingSummaryState() {
        // Pre-seed with realistic .readingSummary residue (the case that would
        // immediately precede this in production). Without explicit cleanup the
        // stale "steps (14/14)" would bleed into the bridge UI.
        let vm = HomeViewModelTests.makeViewModel()
        vm.stagePrefix = "> totals · "
        vm.stageLabel = "steps"
        vm.stageCounter = "(14/14)"

        vm.updateStage(.startingSamplesFetch)

        XCTAssertEqual(vm.currentStage, "> starting raw samples…")
        XCTAssertNil(vm.stageLabel, "must clear residue from preceding .readingSummary")
        XCTAssertNil(vm.stageCounter, "must clear residue from preceding .readingSummary")
    }

    @MainActor
    func test_updateStage_readingSamples_multi() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.readingSamples(categoryID: "heart_rate", completed: 4, total: 14))
        XCTAssertEqual(vm.currentStage, "> samples · heart rate (4/14)")
    }

    @MainActor
    func test_updateStage_serializing_multi() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.serializing(day: 0, totalDays: 7))
        XCTAssertEqual(vm.currentStage, "> writing 7 snapshots…")
    }

    @MainActor
    func test_updateStage_serializing_clearsPriorReadingSamplesState() {
        // Pre-seed with .readingSamples residue (last event before .serializing).
        let vm = HomeViewModelTests.makeViewModel()
        vm.stagePrefix = "> samples · "
        vm.stageLabel = "workouts"
        vm.stageCounter = "(14/14)"

        vm.updateStage(.serializing(day: 0, totalDays: 7))

        XCTAssertEqual(vm.currentStage, "> writing 7 snapshots…")
        XCTAssertNil(vm.stageLabel)
        XCTAssertNil(vm.stageCounter)
    }

    @MainActor
    func test_updateStage_serializing_single() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.serializing(day: 0, totalDays: 1))
        XCTAssertEqual(vm.currentStage, "> writing snapshot…")
    }

    @MainActor
    func test_updateStage_delivering_isOneIndexed() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.delivering(sinkID: "github", day: 0, totalDays: 7))
        XCTAssertEqual(vm.currentStage, "> github: pushing day 1/7",
                       "1-indexed regression test")
    }

    @MainActor
    func test_updateStage_delivering_singleDay() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.delivering(sinkID: "github", day: 0, totalDays: 1))
        XCTAssertEqual(vm.currentStage, "> github: pushing…")
    }

    @MainActor
    func test_updateStage_retrying() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.updateStage(.retrying(sinkID: "github", attempt: 2, totalAttempts: 4, reason: "non-fast-forward"))
        XCTAssertEqual(vm.currentStage, "> github: retry 2/4 · non-fast-forward")
    }

    @MainActor
    func test_updateStage_finished_resetsAllFields() {
        let vm = HomeViewModelTests.makeViewModel()
        vm.stagePrefix = "anything"
        vm.stageLabel = "x"
        vm.stageCounter = "(1/1)"
        vm.updateStage(.finished)
        XCTAssertEqual(vm.stagePrefix, "")
        XCTAssertNil(vm.stageLabel)
        XCTAssertNil(vm.stageCounter)
    }
}

@MainActor
private final class ObservedPhases {
    var phases: [HomeViewModel.Phase] = []
    func append(_ p: HomeViewModel.Phase) { phases.append(p) }
}
