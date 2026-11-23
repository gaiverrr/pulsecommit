import Foundation
import HealthCore

actor DeviceFlowSession {
    enum State: Equatable, Sendable {
        case idle
        case awaitingApproval(DeviceCodeResponse)
        case approving
        case completed(StoredTokens)
        case failed(GitHubAuthError)
        case cancelled
    }

    private(set) var state: State = .idle

    nonisolated let states: AsyncStream<State>
    private let continuation: AsyncStream<State>.Continuation
    private var observers: [UUID: AsyncStream<State>.Continuation] = [:]

    private let start: @Sendable () async throws -> DeviceCodeResponse
    private let poll: @Sendable (String, Int, Date) async throws -> TokenPair
    private let vault: TokenVault

    private var pollingTask: Task<Void, Never>?
    private var isCancelled = false

    init(
        vault: TokenVault,
        start: @escaping @Sendable () async throws -> DeviceCodeResponse,
        poll: @escaping @Sendable (String, Int, Date) async throws -> TokenPair
    ) {
        self.vault = vault
        self.start = start
        self.poll = poll
        let (stream, cont) = AsyncStream.makeStream(of: State.self)
        self.states = stream
        self.continuation = cont
    }

    static func make(vault: TokenVault, client: GitHubDeviceFlowClient) -> DeviceFlowSession {
        DeviceFlowSession(
            vault: vault,
            start: { try await client.startDeviceFlow() },
            poll: { code, interval, expiresAt in
                try await client.pollForToken(deviceCode: code, interval: interval, expiresAt: expiresAt)
            }
        )
    }

    func begin() async {
        pollingTask?.cancel()
        pollingTask = nil
        isCancelled = false
        do {
            let response = try await start()
            if isCancelled { return }
            publish(.awaitingApproval(response))
            pollingTask = Task { [response] in
                await self.runPolling(response: response)
            }
        } catch let error as GitHubAuthError {
            if isCancelled { return }
            publish(.failed(error))
        } catch let urlError as URLError {
            if isCancelled { return }
            publish(.failed(.network(urlError)))
        } catch {
            if isCancelled { return }
            publish(.failed(.unexpected(statusCode: -1, errorCode: nil)))
        }
    }

    func cancel() async {
        switch state {
        case .completed, .cancelled:
            return
        case .idle, .awaitingApproval, .approving, .failed:
            break
        }
        isCancelled = true
        let task = pollingTask
        task?.cancel()
        // A cancelled attempt may already be inside `vault.save`. Do not make
        // the destination reconnectable until that task has finished its
        // cancellation cleanup, or its final clear could erase newer tokens.
        await task?.value
        pollingTask = nil
        publish(.cancelled)
    }

    private func runPolling(response: DeviceCodeResponse) async {
        if isCancelled { return }
        publish(.approving)
        do {
            let pair = try await poll(response.deviceCode, response.interval, response.expiresAt)
            if Task.isCancelled || isCancelled { return }
            let stored = StoredTokens(
                accessToken: pair.accessToken,
                refreshToken: pair.refreshToken,
                accessExpiresAt: pair.accessExpiresAt,
                refreshExpiresAt: pair.refreshExpiresAt
            )
            try await vault.save(stored)
            if Task.isCancelled || isCancelled {
                try? await vault.clear()
                return
            }
            publish(.completed(stored))
        } catch is CancellationError {
            return
        } catch let error as GitHubAuthError {
            if Task.isCancelled { return }
            publish(.failed(error))
        } catch let urlError as URLError {
            if Task.isCancelled { return }
            publish(.failed(.network(urlError)))
        } catch {
            if Task.isCancelled { return }
            publish(.failed(.unexpected(statusCode: -1, errorCode: nil)))
        }
    }

    private func publish(_ next: State) {
        state = next
        continuation.yield(next)
        for (_, observer) in observers {
            observer.yield(next)
        }
        if isTerminal(next) {
            for (_, observer) in observers {
                observer.finish()
            }
            observers.removeAll()
        }
    }

    private func isTerminal(_ state: State) -> Bool {
        switch state {
        case .completed, .failed, .cancelled:
            return true
        case .idle, .awaitingApproval, .approving:
            return false
        }
    }

    /// Returns an independent `AsyncStream` that mirrors every state event
    /// published by this session. Used by `GitHubDestinationViewModel` so it
    /// can observe `.completed` without competing with the device-code VM for
    /// events on `states`.
    ///
    /// The legacy AsyncStream pathway remains for the UI caller. Cleanup of
    /// the observer slot is bridged to the actor via a fire-and-forget Task
    /// because `AsyncStream.onTermination` is a non-async closure — actor
    /// mutation cannot otherwise be invoked from it.
    func observe() -> AsyncStream<State> {
        AsyncStream { continuation in
            let id = UUID()
            observers[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeObserver(id: id) }
            }
        }
    }

    /// Structured variant of `observe()`: invokes `body` for every state event
    /// until either the session reaches a terminal state or the surrounding
    /// task is cancelled. Observer slot teardown runs inside a
    /// `withTaskCancellationHandler`, so cancellation deterministically
    /// removes the observer without an orphaned Task on the cleanup path.
    func observeStructured(_ body: @Sendable (State) async -> Void) async {
        let id = UUID()
        let (stream, continuation) = AsyncStream<State>.makeStream()
        observers[id] = continuation
        await withTaskCancellationHandler {
            for await event in stream {
                await body(event)
            }
            removeObserver(id: id)
        } onCancel: { [weak self] in
            guard let self else { return }
            Task { await self.removeObserver(id: id) }
        }
    }

    private func removeObserver(id: UUID) {
        observers.removeValue(forKey: id)
    }

    #if DEBUG
    /// Test-only accessor for the live observer count. Used to assert that
    /// `observeStructured` deterministically tears down the observer slot on
    /// cancellation (pc-6wd).
    func _observerCountForTesting() -> Int {
        observers.count
    }
    #endif
}
