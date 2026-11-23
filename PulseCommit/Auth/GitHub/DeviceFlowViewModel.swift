import Foundation
import Observation
import HealthCore

@MainActor
@Observable
final class DeviceFlowViewModel {
    enum DisplayState: Equatable {
        case idle
        case awaitingApproval
        case approving
        case completed
        case failed
        case cancelled
    }

    var state: DisplayState = .idle
    var userCode: String?
    var verificationURI: URL?
    var errorMessage: String?
    let id = UUID()

    private let states: AsyncStream<DeviceFlowSession.State>
    private let beginAction: @Sendable () async -> Void
    private let cancelAction: @Sendable () async -> Void

    private var consumer: Task<Void, Never>?

    init(
        states: AsyncStream<DeviceFlowSession.State>,
        begin: @escaping @Sendable () async -> Void,
        cancel: @escaping @Sendable () async -> Void
    ) {
        self.states = states
        self.beginAction = begin
        self.cancelAction = cancel
    }

    static func live(session: DeviceFlowSession) -> DeviceFlowViewModel {
        DeviceFlowViewModel(
            states: session.states,
            begin: { await session.begin() },
            cancel: { await session.cancel() }
        )
    }

    func begin() {
        consumer?.cancel()
        state = .idle
        userCode = nil
        verificationURI = nil
        errorMessage = nil
        let stream = states
        consumer = Task { [weak self] in
            for await next in stream {
                guard let self else { return }
                self.apply(next)
                if Task.isCancelled { return }
            }
        }
        Task { [beginAction] in
            await beginAction()
        }
    }

    func cancel() {
        Task { [cancelAction] in
            await cancelAction()
        }
    }

    private func apply(_ next: DeviceFlowSession.State) {
        switch next {
        case .idle:
            state = .idle
        case .awaitingApproval(let response):
            state = .awaitingApproval
            userCode = response.userCode
            verificationURI = response.verificationURIComplete
        case .approving:
            state = .approving
        case .completed:
            state = .completed
        case .failed(let error):
            state = .failed
            userCode = nil
            verificationURI = nil
            errorMessage = error.userFacingMessage
        case .cancelled:
            state = .cancelled
        }
    }
}
