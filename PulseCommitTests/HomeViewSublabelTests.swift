import XCTest
@testable import PulseCommit

@MainActor
final class HomeViewSublabelTests: XCTestCase {
    private func makeViewModelInPhase(_ phase: HomeViewModel.Phase) -> HomeViewModel {
        let vm = HomeViewModelTests.makeViewModel()
        vm.phase = phase
        return vm
    }

    func test_buttonSubLabel_isNilDuringRunning() {
        let vm = makeViewModelInPhase(.running)
        XCTAssertNil(HomeView.computeButtonSubLabel(for: vm, periodSubLabel: "ignored"))
    }

    func test_buttonSubLabel_returnsPeriodSubLabelOnIdle() {
        let vm = makeViewModelInPhase(.idle)
        XCTAssertEqual(
            HomeView.computeButtonSubLabel(for: vm, periodSubLabel: "Today · ready"),
            "Today · ready"
        )
    }

    func test_buttonSubLabel_doneIncludesRelativeTime() {
        let fixedDate = Date(timeIntervalSinceNow: -120) // 2 minutes ago
        let vm = makeViewModelInPhase(.done(at: fixedDate))
        let label = HomeView.computeButtonSubLabel(for: vm, periodSubLabel: "ignored")
        XCTAssertNotNil(label)
        XCTAssertTrue(label!.hasPrefix("Last commit · "), "got: \(label ?? "nil")")
        XCTAssertTrue(label!.hasSuffix(" · ✓"), "got: \(label ?? "nil")")
    }

    func test_buttonSubLabel_errorIsReasonWithoutPrefix() {
        let vm = makeViewModelInPhase(.error(reason: "boom"))
        XCTAssertEqual(
            HomeView.computeButtonSubLabel(for: vm, periodSubLabel: "ignored"),
            "boom"
        )
    }

    func test_subLabelAction_errorWithEntryOpensThatEntry() {
        let id = UUID()
        XCTAssertEqual(HomeView.subLabelAction(for: .error(reason: "boom", entryId: id)), .openEntry(id))
    }

    func test_subLabelAction_errorWithoutEntryHasNoAction() {
        XCTAssertEqual(HomeView.subLabelAction(for: .error(reason: "boom", entryId: nil)), SubLabelAction.none)
    }

    func test_subLabelAction_idleAndDoneExport() {
        XCTAssertEqual(HomeView.subLabelAction(for: .idle), .export)
        XCTAssertEqual(HomeView.subLabelAction(for: .done(at: Date())), .export)
    }

    func test_subLabelAction_runningHasNoAction() {
        XCTAssertEqual(HomeView.subLabelAction(for: .running), SubLabelAction.none)
    }

    func test_accessibilityHint_errorWithoutEntryKeepsReason() {
        let vm = makeViewModelInPhase(.error(reason: "boom", entryId: nil))
        let label = HomeView.computeButtonSubLabel(for: vm, periodSubLabel: "ignored")
        XCTAssertEqual(HomeView.accessibilityHintText(for: vm, buttonSubLabel: label), "boom")
    }

    func test_accessibilityHint_inErrorDoesNotRepeatReason() {
        let vm = makeViewModelInPhase(.error(reason: "boom", entryId: UUID()))
        let label = HomeView.computeButtonSubLabel(for: vm, periodSubLabel: "ignored")
        XCTAssertEqual(HomeView.accessibilityHintText(for: vm, buttonSubLabel: label), "")
    }

    func test_accessibilityHint_isStaticDuringRunning() {
        let vm = makeViewModelInPhase(.running)
        vm.stagePrefix = "> totals · "
        vm.stageLabel = "steps"
        vm.stageCounter = "(3/14)"
        let hint = HomeView.accessibilityHintText(for: vm, buttonSubLabel: nil)
        XCTAssertEqual(hint, "Export in progress",
                       "hint must be static during running to avoid VoiceOver spam")
    }
}
