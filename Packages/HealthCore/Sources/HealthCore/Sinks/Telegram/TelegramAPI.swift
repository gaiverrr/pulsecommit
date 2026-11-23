import Foundation

public enum TelegramAPI {
    public static let baseURL = URL(string: "https://api.telegram.org")!

    public static func sendMessageRequest(
        credentials: TelegramCredentials,
        text: String,
        disableWebPagePreview: Bool = true
    ) throws -> URLRequest {
        let url = methodURL(botToken: credentials.botToken, method: "sendMessage")
        var body: [String: Any] = [
            "chat_id": credentials.chatID,
            "text": text,
            "parse_mode": "MarkdownV2",
            "disable_web_page_preview": disableWebPagePreview
        ]
        if let threadId = credentials.messageThreadID {
            body["message_thread_id"] = threadId
        }
        let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        return request
    }

    public static func sendDocumentRequest(
        credentials: TelegramCredentials,
        filename: String,
        data: Data,
        caption: String?
    ) -> URLRequest {
        let url = methodURL(botToken: credentials.botToken, method: "sendDocument")
        let boundary = "PulseCommitBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(
            boundary: boundary,
            chatID: credentials.chatID,
            caption: caption,
            filename: filename,
            documentData: data,
            messageThreadID: credentials.messageThreadID
        )
        return request
    }

    static func multipartBody(
        boundary: String,
        chatID: String,
        caption: String?,
        filename: String,
        documentData: Data,
        messageThreadID: Int? = nil
    ) -> Data {
        var body = Data()
        let delimiter = "--\(boundary)\r\n"

        func appendField(name: String, value: String) {
            body.append(delimiter.data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "chat_id", value: chatID)
        if let messageThreadID {
            appendField(name: "message_thread_id", value: String(messageThreadID))
        }
        if let caption {
            appendField(name: "caption", value: caption)
        }

        body.append(delimiter.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"document\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/zip\r\n\r\n".data(using: .utf8)!)
        body.append(documentData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private static func methodURL(botToken: String, method: String) -> URL {
        baseURL
            .appendingPathComponent("bot\(botToken)")
            .appendingPathComponent(method)
    }
}
