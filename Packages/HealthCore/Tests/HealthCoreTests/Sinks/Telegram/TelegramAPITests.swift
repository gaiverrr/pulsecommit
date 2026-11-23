import XCTest
@testable import HealthCore

final class TelegramAPITests: XCTestCase {
    private let credentials = TelegramCredentials(
        botToken: "123:ABC",
        chatID: "-100987",
        verbosity: .standard,
        includeGitHubLink: true
    )

    func testSendMessageRequestURLAndHeaders() throws {
        let request = try TelegramAPI.sendMessageRequest(credentials: credentials, text: "hello")

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.telegram.org/bot123:ABC/sendMessage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testSendMessageRequestJSONBody() throws {
        let request = try TelegramAPI.sendMessageRequest(credentials: credentials, text: "hello *world*")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(json["chat_id"] as? String, "-100987")
        XCTAssertEqual(json["text"] as? String, "hello *world*")
        XCTAssertEqual(json["parse_mode"] as? String, "MarkdownV2")
        XCTAssertEqual(json["disable_web_page_preview"] as? Bool, true)
    }

    func testSendDocumentRequestURLAndContentType() {
        let request = TelegramAPI.sendDocumentRequest(
            credentials: credentials,
            filename: "pulse-commit-2026-05-14.zip",
            data: Data([0x50, 0x4B]),
            caption: "JSON archive · 6 files · schema 1.0"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.telegram.org/bot123:ABC/sendDocument")
        let contentType = try? XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType?.hasPrefix("multipart/form-data; boundary=") == true)
    }

    func testSendDocumentMultipartBodyContainsExpectedFields() throws {
        let docBytes = Data([0x50, 0x4B, 0x03, 0x04, 0xFF, 0x00])
        let request = TelegramAPI.sendDocumentRequest(
            credentials: credentials,
            filename: "pulse-commit-2026-05-14.zip",
            data: docBytes,
            caption: "JSON archive · 6 files · schema 1.0"
        )
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""

        XCTAssertTrue(bodyString.contains("name=\"chat_id\""))
        XCTAssertTrue(bodyString.contains("-100987"))
        XCTAssertTrue(bodyString.contains("name=\"caption\""))
        XCTAssertTrue(bodyString.contains("JSON archive"))
        XCTAssertTrue(bodyString.contains("name=\"document\"; filename=\"pulse-commit-2026-05-14.zip\""))
        XCTAssertTrue(bodyString.contains("Content-Type: application/zip"))
        XCTAssertNotNil(body.range(of: docBytes))
    }

    func testSendMessageIncludesMessageThreadIdWhenSet() throws {
        let threadCredentials = TelegramCredentials(
            botToken: "123:ABC",
            chatID: "-100987",
            verbosity: .standard,
            includeGitHubLink: true,
            messageThreadID: 42
        )
        let request = try TelegramAPI.sendMessageRequest(credentials: threadCredentials, text: "hi")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["message_thread_id"] as? Int, 42)
    }

    func testSendMessageOmitsMessageThreadIdWhenNil() throws {
        let request = try TelegramAPI.sendMessageRequest(credentials: credentials, text: "hi")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(json["message_thread_id"])
    }

    func testSendDocumentIncludesMessageThreadIdWhenSet() throws {
        let threadCredentials = TelegramCredentials(
            botToken: "123:ABC",
            chatID: "-100987",
            verbosity: .standard,
            includeGitHubLink: true,
            messageThreadID: 42
        )
        let request = TelegramAPI.sendDocumentRequest(
            credentials: threadCredentials,
            filename: "x.zip",
            data: Data([0x01]),
            caption: nil
        )
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        XCTAssertTrue(bodyString.contains("name=\"message_thread_id\""))
        XCTAssertTrue(bodyString.contains("\r\n\r\n42\r\n"))
    }

    func testSendDocumentOmitsMessageThreadIdWhenNil() throws {
        let request = TelegramAPI.sendDocumentRequest(
            credentials: credentials,
            filename: "x.zip",
            data: Data([0x01]),
            caption: nil
        )
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        XCTAssertFalse(bodyString.contains("name=\"message_thread_id\""))
    }

    func testSendDocumentOmitsCaptionWhenNil() throws {
        let request = TelegramAPI.sendDocumentRequest(
            credentials: credentials,
            filename: "x.zip",
            data: Data([0x01]),
            caption: nil
        )
        let body = try XCTUnwrap(request.httpBody)
        let bodyString = String(data: body, encoding: .isoLatin1) ?? ""
        XCTAssertFalse(bodyString.contains("name=\"caption\""))
    }
}
