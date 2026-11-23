import XCTest
@testable import PulseCommit

@MainActor
final class GitHubConnectedViewTests: XCTestCase {
    func test_confirmDisconnect_invokesDisconnectThenOnDisconnected() async {
        let disconnectCalled = expectation(description: "disconnect called")
        let onDisconnected = expectation(description: "onDisconnected called")
        let order = OrderTracker()

        let vm = GitHubConnectedViewModel(
            owner: "octocat",
            repo: "demo",
            branch: "main",
            subdir: "",
            testConnection: { _, _ in .success },
            disconnect: {
                await order.append("disconnect")
                disconnectCalled.fulfill()
            },
            onDisconnected: {
                Task { await order.append("onDisconnected") }
                onDisconnected.fulfill()
            }
        )

        vm.requestDisconnect()
        XCTAssertTrue(vm.showDisconnectConfirm)

        vm.confirmDisconnect()
        XCTAssertFalse(vm.showDisconnectConfirm)

        await fulfillment(of: [disconnectCalled, onDisconnected], timeout: 2.0)
        // Give the onDisconnected Task a moment to record order.
        try? await Task.sleep(nanoseconds: 50_000_000)
        let recorded = await order.values
        XCTAssertEqual(recorded.first, "disconnect")
    }

    func test_cancelDisconnect_doesNotCallDisconnect() async throws {
        var disconnectCalls = 0
        let vm = GitHubConnectedViewModel(
            owner: "o",
            repo: "r",
            branch: "main",
            subdir: "",
            testConnection: { _, _ in .success },
            disconnect: { disconnectCalls += 1 },
            onDisconnected: {}
        )

        vm.requestDisconnect()
        vm.cancelDisconnect()
        XCTAssertFalse(vm.showDisconnectConfirm)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(disconnectCalls, 0)
    }

    func test_runTestConnection_surfacesSuccess() async throws {
        let vm = GitHubConnectedViewModel(
            owner: "octocat",
            repo: "demo",
            branch: "main",
            subdir: "",
            testConnection: { owner, repo in
                XCTAssertEqual(owner, "octocat")
                XCTAssertEqual(repo, "demo")
                return .success
            },
            disconnect: {},
            onDisconnected: {}
        )

        vm.runTestConnection()
        XCTAssertEqual(vm.testResult, .running)

        try await waitUntil(timeout: 2.0) {
            vm.testResult == .success
        }
    }

    func test_runTestConnection_surfacesFailure() async throws {
        let vm = GitHubConnectedViewModel(
            owner: "o",
            repo: "r",
            branch: "main",
            subdir: "",
            testConnection: { _, _ in .failure("HTTP 404") },
            disconnect: {},
            onDisconnected: {}
        )

        vm.runTestConnection()
        try await waitUntil(timeout: 2.0) {
            if case .failure(let msg) = vm.testResult { return msg == "HTTP 404" }
            return false
        }
    }

    func test_previewTree_includesOwnerRepoBranch() {
        let tree = GitHubConnectedView.previewTree(
            owner: "octocat",
            repo: "hello-world",
            branch: "main",
            subdir: ""
        )
        XCTAssertTrue(tree.contains("octocat/hello-world@main"))
        XCTAssertTrue(tree.contains("summary.json"))
        XCTAssertTrue(tree.contains("samples/"))
    }

    func test_previewTree_includesSubdirWhenPresent() {
        let tree = GitHubConnectedView.previewTree(
            owner: "u",
            repo: "r",
            branch: "main",
            subdir: "health"
        )
        XCTAssertTrue(tree.contains("u/r@main:health"))
    }

    private func waitUntil(timeout: TimeInterval, _ predicate: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Condition not met within \(timeout)s")
    }
}

private actor OrderTracker {
    private(set) var values: [String] = []
    func append(_ v: String) { values.append(v) }
}
