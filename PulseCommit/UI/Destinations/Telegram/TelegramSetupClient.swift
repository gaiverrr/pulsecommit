import Foundation
import HealthCore

enum TelegramSetupError: Error, Equatable, LocalizedError {
    case invalidToken
    case chatNotFound
    case botForbidden
    case threadNotFound
    case networkUnavailable
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Check the bot token in @BotFather, then verify it again."
        case .chatNotFound:
            return "Check the chat ID and add the bot to that chat, then try again."
        case .botForbidden:
            return "Allow the bot to post in this chat. Check its membership and admin permissions."
        case .threadNotFound:
            return "Check the topic's thread ID, or leave it blank to post to the main chat."
        case .networkUnavailable:
            return "Check your internet connection and try again."
        case .unexpectedResponse:
            return "Telegram could not complete the check. Review the bot and chat settings, then try again."
        }
    }
}

/// Setup checks are separate from `TelegramSink`: no Health snapshot,
/// export history, or consent is involved. Only these two Bot API methods are used.
struct TelegramSetupClient {
    static let testMessage = "Pulse Commit setup test. This is a sample message."

    let session: URLSession

    init(session: URLSession = EphemeralAPISession.shared) {
        self.session = session
    }

    func verifyBot(token: String) async throws -> String {
        let request = URLRequest(url: methodURL(token: token, name: "getMe"))
        let data = try await perform(request, method: .getMe, threadID: nil)
        guard let result = try? JSONDecoder().decode(BotResponse.self, from: data),
              result.ok, let username = result.result?.username, !username.isEmpty else {
            throw TelegramSetupError.unexpectedResponse
        }
        return username
    }

    func sendTestMessage(token: String, chatID: String, threadID: Int?) async throws {
        var request = URLRequest(url: methodURL(token: token, name: "sendMessage"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["chat_id": chatID, "text": Self.testMessage]
        if let threadID { body["message_thread_id"] = threadID }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await perform(request, method: .sendMessage, threadID: threadID)
        guard let result = try? JSONDecoder().decode(MessageResponse.self, from: data),
              result.ok, result.result?.message_id != nil else {
            throw TelegramSetupError.unexpectedResponse
        }
    }

    private enum Method { case getMe, sendMessage }

    private func methodURL(token: String, name: String) -> URL {
        TelegramAPI.baseURL.appendingPathComponent("bot\(token)").appendingPathComponent(name)
    }

    private func perform(_ request: URLRequest, method: Method, threadID: Int?) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TelegramSetupError.networkUnavailable
        }
        guard let http = response as? HTTPURLResponse else { throw TelegramSetupError.unexpectedResponse }
        if (200..<300).contains(http.statusCode) { return data }

        // Never surface Telegram's raw response: it may reflect an invalid URL
        // containing the token. Map only known error categories to safe copy.
        let description = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?
            .description?.lowercased() ?? ""
        if http.statusCode == 401 || http.statusCode == 404 {
            throw TelegramSetupError.invalidToken
        }
        if case .sendMessage = method {
            if description.contains("thread") || description.contains("topic") {
                throw TelegramSetupError.threadNotFound
            }
            if http.statusCode == 403 {
                throw TelegramSetupError.botForbidden
            }
            if description.contains("chat") || description.contains("peer") {
                throw TelegramSetupError.chatNotFound
            }
            if threadID != nil && http.statusCode == 400 {
                throw TelegramSetupError.threadNotFound
            }
        }
        throw TelegramSetupError.unexpectedResponse
    }

    private struct BotResponse: Decodable {
        let ok: Bool
        let result: Bot?
        struct Bot: Decodable { let username: String? }
    }

    private struct MessageResponse: Decodable {
        let ok: Bool
        let result: Message?
        struct Message: Decodable { let message_id: Int }
    }

    private struct APIErrorResponse: Decodable { let description: String? }
}
