import XCTest
import UIKit
@testable import PulseCommit

@MainActor
final class GitHubDeviceCodeSheetTests: XCTestCase {
    func test_formatUserCode_eightCharsHyphenated() {
        XCTAssertEqual(GitHubDeviceCodeSheet.formatUserCode("ABCD1234"), "ABCD-1234")
    }

    func test_formatUserCode_keepsExistingHyphen() {
        XCTAssertEqual(GitHubDeviceCodeSheet.formatUserCode("ABCD-1234"), "ABCD-1234")
    }

    func test_formatUserCode_shortInputUnchanged() {
        XCTAssertEqual(GitHubDeviceCodeSheet.formatUserCode("ABC"), "ABC")
    }

    func test_formatUserCode_longInputUnchanged() {
        XCTAssertEqual(GitHubDeviceCodeSheet.formatUserCode("ABCDEFGHIJ"), "ABCDEFGHIJ")
    }

    func test_copyToPasteboard_writesString() {
        let marker = "TEST-\(UUID().uuidString)"
        GitHubDeviceCodeSheet.copyToPasteboard(marker)
        XCTAssertEqual(UIPasteboard.general.string, marker)
    }

    func test_shouldDismiss_trueForCompletedAndCancelled() {
        XCTAssertTrue(GitHubDeviceCodeSheet.shouldDismiss(for: .completed))
        XCTAssertTrue(GitHubDeviceCodeSheet.shouldDismiss(for: .cancelled))
    }

    func test_shouldDismiss_falseForActiveStates() {
        XCTAssertFalse(GitHubDeviceCodeSheet.shouldDismiss(for: .idle))
        XCTAssertFalse(GitHubDeviceCodeSheet.shouldDismiss(for: .awaitingApproval))
        XCTAssertFalse(GitHubDeviceCodeSheet.shouldDismiss(for: .approving))
        XCTAssertFalse(GitHubDeviceCodeSheet.shouldDismiss(for: .failed))
    }

    func test_view_canBeInstantiated() {
        let stream = AsyncStream<DeviceFlowSession.State> { _ in }
        let vm = DeviceFlowViewModel(
            states: stream,
            begin: {},
            cancel: {}
        )
        _ = GitHubDeviceCodeSheet(viewModel: vm, onDismiss: {}, onRetry: {})
    }
}
