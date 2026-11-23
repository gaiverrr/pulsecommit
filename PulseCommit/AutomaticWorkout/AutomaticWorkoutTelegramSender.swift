import Foundation
import HealthCore

struct AutomaticWorkoutTelegramCredentials: Sendable {
    let scopeID: String
    let credentials: TelegramCredentials
}

struct AutomaticWorkoutTelegramSender: AutomaticWorkoutSending {
    let session: URLSession
    let currentCredentials: @Sendable () async -> AutomaticWorkoutTelegramCredentials?
    let clock: @Sendable () -> Date

    init(
        session: URLSession = EphemeralAPISession.shared,
        currentCredentials: @escaping @Sendable () async -> AutomaticWorkoutTelegramCredentials?,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.currentCredentials = currentCredentials
        self.clock = clock
    }

    func send(
        _ candidate: AutomaticWorkoutCandidate,
        scopeID: String,
        timeZoneIdentifier: String
    ) async -> AutomaticWorkoutSendResult {
        guard let current = await currentCredentials(), current.scopeID == scopeID else {
            return .rejected(retryAfter: nil)
        }
        let message = AutomaticWorkoutMessageRenderer().render(
            workout: candidate.workout,
            timeZoneIdentifier: timeZoneIdentifier
        )
        let request: URLRequest
        do {
            var built = try TelegramAPI.sendMessageRequest(credentials: current.credentials, text: message)
            built.timeoutInterval = 20
            request = built
        } catch {
            return .rejected(retryAfter: nil)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .deliveryUnknown }
            if (200..<300).contains(http.statusCode) {
                guard let envelope = try? JSONDecoder().decode(SuccessEnvelope.self, from: data),
                      envelope.ok, let messageID = envelope.result?.messageID else {
                    return .deliveryUnknown
                }
                return .delivered(messageID: messageID)
            }
            if http.statusCode == 429 {
                let seconds = (try? JSONDecoder().decode(RateLimitEnvelope.self, from: data))?
                    .parameters?.retryAfter ?? 900
                let serverDelay = max(seconds, 60)
                return .rejected(retryAfter: clock().addingTimeInterval(TimeInterval(serverDelay)))
            }
            if (400..<500).contains(http.statusCode) {
                return .rejected(retryAfter: clock().addingTimeInterval(15 * 60))
            }
            return .deliveryUnknown
        } catch is CancellationError {
            return .deliveryUnknown
        } catch {
            return .deliveryUnknown
        }
    }

    private struct SuccessEnvelope: Decodable {
        let ok: Bool
        let result: Result?
        struct Result: Decodable {
            let messageID: Int
            enum CodingKeys: String, CodingKey { case messageID = "message_id" }
        }
    }

    private struct RateLimitEnvelope: Decodable {
        let parameters: Parameters?
        struct Parameters: Decodable {
            let retryAfter: Int
            enum CodingKeys: String, CodingKey { case retryAfter = "retry_after" }
        }
    }
}
