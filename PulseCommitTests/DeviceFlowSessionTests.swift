import XCTest
import HealthCore
@testable import PulseCommit

final class DeviceFlowSessionTests: XCTestCase {
    private actor BlockingSaveVault: TokenVault {
        private var tokens: StoredTokens?
        private let saveStarted: AsyncStream<Void>.Continuation
        private var saveContinuation: CheckedContinuation<Void, Never>?

        init(saveStarted: AsyncStream<Void>.Continuation) {
            self.saveStarted = saveStarted
        }

        func load() async throws -> StoredTokens? { tokens }

        func save(_ tokens: StoredTokens) async throws {
            saveStarted.yield(())
            await withCheckedContinuation { continuation in
                saveContinuation = continuation
            }
            self.tokens = tokens
        }

        func releaseSave() {
            saveContinuation?.resume()
            saveContinuation = nil
        }

        func clear() async throws {
            tokens = nil
        }
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

    private func collect(
        from session: DeviceFlowSession,
        until predicate: @escaping @Sendable (DeviceFlowSession.State) -> Bool,
        timeout: TimeInterval = 5
    ) async throws -> [DeviceFlowSession.State] {
        let stream = session.states
        return try await withThrowingTaskGroup(of: [DeviceFlowSession.State].self) { group in
            group.addTask {
                var collected: [DeviceFlowSession.State] = []
                for await state in stream {
                    collected.append(state)
                    if predicate(state) { break }
                }
                return collected
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TimeoutError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private struct TimeoutError: Error {}

    func test_begin_successPath_publishesAwaitingThenCompleted() async throws {
        let vault = InMemoryTokenVault()
        let response = sampleResponse()
        let pair = samplePair()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in pair }
        )

        let collector = Task {
            try await self.collect(from: session) { state in
                if case .completed = state { return true }
                return false
            }
        }

        await session.begin()
        let states = try await collector.value

        XCTAssertTrue(states.contains(.awaitingApproval(response)))
        guard case .completed(let stored) = states.last else {
            XCTFail("expected completed final state, got \(String(describing: states.last))")
            return
        }
        XCTAssertEqual(stored.accessToken, pair.accessToken)
        XCTAssertEqual(stored.refreshToken, pair.refreshToken)

        let persisted = try await vault.load()
        XCTAssertEqual(persisted?.accessToken, pair.accessToken)
    }

    func test_cancel_afterCompletion_preservesCompletedStateAndTokens() async throws {
        let vault = InMemoryTokenVault()
        let response = sampleResponse()
        let pair = samplePair()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in pair }
        )

        let collector = Task {
            try await self.collect(from: session) { state in
                if case .completed = state { return true }
                return false
            }
        }
        await session.begin()
        _ = try await collector.value

        await session.cancel()

        let finalState = await session.state
        let persisted = try await vault.load()
        guard case .completed = finalState else {
            return XCTFail("completed authorization must not become cancelled")
        }
        XCTAssertEqual(persisted?.accessToken, pair.accessToken)
    }

    func test_cancel_duringAwait_transitionsToCancelled() async throws {
        let vault = InMemoryTokenVault()
        let response = sampleResponse()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                throw CancellationError()
            }
        )

        let collector = Task {
            try await self.collect(from: session) { state in
                state == .cancelled
            }
        }

        await session.begin()
        // give the polling task a moment to start
        try await Task.sleep(nanoseconds: 50_000_000)
        await session.cancel()

        let states = try await collector.value
        XCTAssertEqual(states.last, .cancelled)
        let persisted = try await vault.load()
        XCTAssertNil(persisted)
    }

    func test_cancel_waitsForInFlightVaultCleanupBeforePublishingCancelled() async throws {
        let saveStarted = AsyncStream<Void>.makeStream()
        let vault = BlockingSaveVault(saveStarted: saveStarted.continuation)
        let response = sampleResponse()
        let pair = samplePair()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in pair }
        )

        await session.begin()
        for await _ in saveStarted.stream { break }

        let cancellation = Task { await session.cancel() }
        try await Task.sleep(nanoseconds: 50_000_000)
        let stateBeforeCleanup = await session.state
        XCTAssertNotEqual(
            stateBeforeCleanup,
            .cancelled,
            "the destination must stay unavailable until the cancelled attempt finishes vault cleanup"
        )

        await vault.releaseSave()
        _ = await cancellation.value

        let finalState = await session.state
        let storedTokens = try await vault.load()
        XCTAssertEqual(finalState, .cancelled)
        XCTAssertNil(storedTokens)
    }

    func test_pollFailsCodeExpired_publishesFailed() async throws {
        let vault = InMemoryTokenVault()
        let response = sampleResponse()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in
                throw GitHubAuthError.codeExpired
            }
        )

        let collector = Task {
            try await self.collect(from: session) { state in
                if case .failed = state { return true }
                return false
            }
        }

        await session.begin()
        let states = try await collector.value
        XCTAssertEqual(states.last, .failed(.codeExpired))
        let persisted = try await vault.load()
        XCTAssertNil(persisted)
    }

    func test_observe_observerTaskCancellation_stopsReceivingEvents() async throws {
        // Regression for wave-3 M-2: when the consumer of `observe()` cancels its
        // task (e.g. the GitHubDestinationView disappearing), no further events
        // should be processed and the observer must be removed from the session.
        let vault = InMemoryTokenVault()
        let response = sampleResponse()
        let gate = AsyncStream<Void>.makeStream()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in
                // Park inside polling so the session stays alive while we exercise
                // observer-side cancellation.
                for await _ in gate.stream { break }
                throw CancellationError()
            }
        )

        actor Counter {
            private(set) var count = 0
            func bump() { count += 1 }
        }
        let counter = Counter()

        let stream = await session.observe()
        let observerTask = Task {
            for await _ in stream {
                await counter.bump()
            }
        }

        await session.begin()
        // Let the session publish `.awaitingApproval` and `.approving` to the observer.
        try await Task.sleep(nanoseconds: 80_000_000)
        let before = await counter.count
        XCTAssertGreaterThanOrEqual(before, 1)

        observerTask.cancel()
        // Wait for the AsyncStream onTermination → removeObserver to run.
        _ = await observerTask.value
        try await Task.sleep(nanoseconds: 50_000_000)

        // Drive another publish — the cancelled observer must not see it.
        gate.continuation.yield(())
        await session.cancel()
        try await Task.sleep(nanoseconds: 80_000_000)

        let after = await counter.count
        XCTAssertEqual(after, before, "observer must stop receiving events after cancellation")
    }

    /// pc-6wd: `observeStructured` must remove its observer slot
    /// deterministically — both on natural termination AND on consumer
    /// cancellation — instead of relying on a fire-and-forget Task from
    /// `AsyncStream.onTermination`.
    func test_observeStructured_removesObserverOnCancellation() async throws {
        let vault = InMemoryTokenVault()
        let response = sampleResponse()
        let gate = AsyncStream<Void>.makeStream()
        let session = DeviceFlowSession(
            vault: vault,
            start: { response },
            poll: { _, _, _ in
                for await _ in gate.stream { break }
                throw CancellationError()
            }
        )

        actor Counter {
            private(set) var count = 0
            func bump() { count += 1 }
        }
        let counter = Counter()

        let observerTask = Task {
            await session.observeStructured { _ in
                await counter.bump()
            }
        }

        // Wait for the observer to be registered before publishing.
        for _ in 0..<200 where await session._observerCountForTesting() == 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let observersBefore = await session._observerCountForTesting()
        XCTAssertEqual(observersBefore, 1)

        await session.begin()
        try await Task.sleep(nanoseconds: 100_000_000)
        let countBefore = await counter.count
        XCTAssertGreaterThanOrEqual(countBefore, 1)

        observerTask.cancel()
        _ = await observerTask.value
        // Yield long enough for the onCancel cleanup Task to run on the actor.
        try await Task.sleep(nanoseconds: 100_000_000)

        let observersAfter = await session._observerCountForTesting()
        XCTAssertEqual(observersAfter, 0, "observer must be removed after cancellation")

        gate.continuation.yield(())
        await session.cancel()
    }

    func test_startFailsNetwork_publishesFailed() async throws {
        let vault = InMemoryTokenVault()
        let urlError = URLError(.notConnectedToInternet)
        let session = DeviceFlowSession(
            vault: vault,
            start: { throw GitHubAuthError.network(urlError) },
            poll: { _, _, _ in throw GitHubAuthError.codeExpired }
        )

        let collector = Task {
            try await self.collect(from: session) { state in
                if case .failed = state { return true }
                return false
            }
        }

        await session.begin()
        let states = try await collector.value
        XCTAssertEqual(states.last, .failed(.network(urlError)))
    }
}
