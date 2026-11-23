import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class DeviceFlowViewModelTests: XCTestCase {
    func test_authPresentationUsesSafeCoreDescription() {
        let error = GitHubAuthError.unexpected(statusCode: 200, errorCode: "incorrect_client_credentials")
        XCTAssertEqual(error.userFacingMessage, error.localizedDescription)
        XCTAssertEqual(error.userFacingMessage, "Unexpected response from GitHub (HTTP 200; incorrect_client_credentials).")
    }

    private func sampleResponse() -> DeviceCodeResponse {
        DeviceCodeResponse(
            deviceCode: "device-xyz",
            userCode: "ABCD-1234",
            verificationURI: URL(string: "https://github.com/login/device")!,
            verificationURIComplete: URL(string: "https://github.com/login/device?user_code=ABCD-1234")!,
            expiresIn: 900,
            interval: 5,
            expiresAt: Date(timeIntervalSinceNow: 900)
        )
    }

    private func samplePair() -> TokenPair {
        TokenPair(
            accessToken: "gho_access",
            refreshToken: "ghr_refresh",
            accessExpiresAt: Date(timeIntervalSinceNow: 28_800),
            refreshExpiresAt: Date(timeIntervalSinceNow: 15_552_000)
        )
    }

    private func makeStored() -> StoredTokens {
        let pair = samplePair()
        return StoredTokens(
            accessToken: pair.accessToken,
            refreshToken: pair.refreshToken,
            accessExpiresAt: pair.accessExpiresAt,
            refreshExpiresAt: pair.refreshExpiresAt
        )
    }

    private func makeVM(
        states: AsyncStream<DeviceFlowSession.State>,
        beginCounter: BeginCounter = BeginCounter(),
        cancelCounter: BeginCounter = BeginCounter()
    ) -> DeviceFlowViewModel {
        DeviceFlowViewModel(
            states: states,
            begin: { await beginCounter.increment() },
            cancel: { await cancelCounter.increment() }
        )
    }

    actor BeginCounter {
        private(set) var count: Int = 0
        func increment() { count += 1 }
        func value() -> Int { count }
    }

    private func waitFor(
        _ vm: DeviceFlowViewModel,
        predicate: @escaping @MainActor (DeviceFlowViewModel) -> Bool,
        timeout: TimeInterval = 2
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate(vm) { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail("timed out waiting for predicate")
    }

    func test_mirrorsAwaitingApproval_populatesUserCodeAndURL() async throws {
        let (stream, cont) = AsyncStream.makeStream(of: DeviceFlowSession.State.self)
        let beginCounter = BeginCounter()
        let vm = makeVM(states: stream, beginCounter: beginCounter)

        let response = sampleResponse()
        vm.begin()

        cont.yield(.awaitingApproval(response))
        try await waitFor(vm) { $0.state == .awaitingApproval }

        XCTAssertEqual(vm.userCode, "ABCD-1234")
        XCTAssertEqual(vm.verificationURI, response.verificationURIComplete)
        XCTAssertNil(vm.errorMessage)

        let calls = await beginCounter.value()
        XCTAssertEqual(calls, 1)
    }

    func test_completed_setsStateCompleted() async throws {
        let (stream, cont) = AsyncStream.makeStream(of: DeviceFlowSession.State.self)
        let vm = makeVM(states: stream)
        vm.begin()

        cont.yield(.awaitingApproval(sampleResponse()))
        cont.yield(.approving)
        cont.yield(.completed(makeStored()))

        try await waitFor(vm) { $0.state == .completed }
    }

    func test_failed_setsUserFacingErrorMessage() async throws {
        let (stream, cont) = AsyncStream.makeStream(of: DeviceFlowSession.State.self)
        let vm = makeVM(states: stream)
        vm.begin()

        cont.yield(.failed(.codeExpired))
        try await waitFor(vm) { $0.state == .failed }

        XCTAssertEqual(vm.errorMessage, GitHubAuthError.codeExpired.userFacingMessage)
    }

    func test_failed_clearsExpiredCodeAndVerificationURL() async throws {
        let (stream, cont) = AsyncStream.makeStream(of: DeviceFlowSession.State.self)
        let vm = makeVM(states: stream)
        vm.begin()

        cont.yield(.awaitingApproval(sampleResponse()))
        try await waitFor(vm) { $0.state == .awaitingApproval }
        XCTAssertNotNil(vm.userCode)
        XCTAssertNotNil(vm.verificationURI)

        cont.yield(.failed(.codeExpired))
        try await waitFor(vm) { $0.state == .failed }

        XCTAssertNil(vm.userCode)
        XCTAssertNil(vm.verificationURI)
    }

    func test_cancel_invokesCancelAction_andCancelledStateMirrors() async throws {
        let (stream, cont) = AsyncStream.makeStream(of: DeviceFlowSession.State.self)
        let cancelCounter = BeginCounter()
        let vm = makeVM(states: stream, cancelCounter: cancelCounter)
        vm.begin()
        vm.cancel()

        cont.yield(.cancelled)
        try await waitFor(vm) { $0.state == .cancelled }

        try await waitFor(vm) { _ in true } // yield
        let calls = await cancelCounter.value()
        XCTAssertEqual(calls, 1)
    }

    func test_userFacingMessage_coversAllCases() {
        let cases: [GitHubAuthError] = [
            .sessionExpired,
            .userDenied,
            .codeExpired,
            .slowDown,
            .authorizationPending,
            .network(URLError(.notConnectedToInternet)),
            .unexpected(statusCode: 500, errorCode: nil)
        ]
        for error in cases {
            XCTAssertFalse(error.userFacingMessage.isEmpty, "missing message for \(error)")
        }
    }
}
