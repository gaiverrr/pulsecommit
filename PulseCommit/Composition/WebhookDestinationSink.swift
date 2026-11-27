import Foundation
import HealthCore

struct WebhookDeliveryError: LocalizedError, Equatable {
    let host: String
    let reason: String

    var errorDescription: String? { "webhook \(host): \(reason)" }
}

final class WebhookDestinationSink: Sink {
    static let sinkID = "webhook"

    let id = WebhookDestinationSink.sinkID
    private let sink: WebhookSink

    init(sink: WebhookSink) {
        self.sink = sink
    }

    static func reference(host: String, statusCode: Int) -> String {
        "\(host) · HTTP \(statusCode)"
    }

    func deliver(snapshot: DailySnapshot, files: [FileEntry]) async throws -> SinkResult {
        try await deliver(snapshot: snapshot, files: files, onAttempt: nil)
    }

    func deliver(
        snapshot: DailySnapshot,
        files: [FileEntry],
        onAttempt: AttemptHandler?
    ) async throws -> SinkResult {
        do {
            let delivery = try await sink.deliverDaily(snapshot: snapshot, files: files, onAttempt: onAttempt)
            return .success(reference: Self.reference(host: sink.host, statusCode: delivery.statusCode), url: nil)
        } catch let error as WebhookSinkError {
            throw WebhookDeliveryError(host: sink.host, reason: error.localizedDescription)
        }
    }
}
