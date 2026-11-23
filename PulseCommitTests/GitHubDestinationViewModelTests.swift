import XCTest
@testable import PulseCommit

@MainActor
final class GitHubDestinationViewModelTests: XCTestCase {
    func test_initialState_isDisconnected() {
        let vm = GitHubDestinationViewModel()
        XCTAssertEqual(vm.state, .disconnected)
    }

    func test_connect_transitionsToAwaitingApproval() {
        let vm = GitHubDestinationViewModel()
        vm.connect()
        XCTAssertEqual(vm.state, .awaitingApproval)
    }

    func test_canStartAttempt_onlyAllowsInitialConnectOrFailedRetry() {
        let vm = GitHubDestinationViewModel()
        XCTAssertTrue(vm.canStartAttempt(deviceFlowState: nil))

        vm.connect()
        XCTAssertFalse(vm.canStartAttempt(deviceFlowState: .idle))
        XCTAssertFalse(vm.canStartAttempt(deviceFlowState: .awaitingApproval))
        XCTAssertTrue(vm.canStartAttempt(deviceFlowState: .failed))

        vm.handleSession(.completed)
        XCTAssertFalse(vm.canStartAttempt(deviceFlowState: nil))
    }

    func test_handleSessionCompleted_transitionsToPickingRepo() {
        let vm = GitHubDestinationViewModel(initialState: .awaitingApproval)
        vm.handleSession(.completed)
        XCTAssertEqual(vm.state, .pickingRepo)
    }

    func test_pickerCompleted_transitionsToConnected() {
        let vm = GitHubDestinationViewModel(initialState: .pickingRepo)
        vm.pickerCompleted()
        XCTAssertEqual(vm.state, .connected)
    }

    func test_pickerCancelled_transitionsToDisconnected() {
        let vm = GitHubDestinationViewModel(initialState: .pickingRepo)
        vm.pickerCancelled()
        XCTAssertEqual(vm.state, .disconnected)
    }

    func test_handleSessionCancelled_transitionsToDisconnected() {
        let vm = GitHubDestinationViewModel(initialState: .awaitingApproval)
        vm.handleSession(.cancelled)
        XCTAssertEqual(vm.state, .disconnected)
    }

    /// A failed device flow must keep the device-code sheet presented so the
    /// user can read the error (`GitHubDeviceCodeSheet.shouldDismiss` returns
    /// false for .failed). The sheet stays up only while the destination state
    /// is .awaitingApproval, so .failed must not collapse to .disconnected.
    func test_handleSessionFailed_keepsAwaitingApprovalSoSheetShowsError() {
        let vm = GitHubDestinationViewModel(initialState: .awaitingApproval)
        vm.handleSession(.failed)
        XCTAssertEqual(vm.state, .awaitingApproval)
    }

    func test_handleSessionApproving_keepsAwaitingApproval() {
        let vm = GitHubDestinationViewModel(initialState: .awaitingApproval)
        vm.handleSession(.approving)
        XCTAssertEqual(vm.state, .awaitingApproval)
    }

    func test_cancel_returnsToDisconnected() {
        let vm = GitHubDestinationViewModel(initialState: .awaitingApproval)
        vm.cancel()
        XCTAssertEqual(vm.state, .disconnected)
    }

    func test_disconnect_returnsToDisconnected() {
        let vm = GitHubDestinationViewModel(initialState: .connected)
        vm.disconnect()
        XCTAssertEqual(vm.state, .disconnected)
    }
}
