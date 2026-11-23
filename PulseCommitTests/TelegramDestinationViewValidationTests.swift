import XCTest
@testable import PulseCommit

final class TelegramDestinationViewValidationTests: XCTestCase {
    func test_emptyString_isInvalid() {
        XCTAssertEqual(ChatIdValidator.validate(""), .invalid)
        XCTAssertEqual(ChatIdValidator.validate("   "), .invalid)
    }

    func test_privateChatId_isValid() {
        XCTAssertEqual(ChatIdValidator.validate("123456"), .valid)
    }

    func test_supergroupWithDash100Prefix_isValid() {
        XCTAssertEqual(ChatIdValidator.validate("-1003232979943"), .valid)
    }

    func test_supergroupMissingDashPrefix_emitsWarning() {
        XCTAssertEqual(ChatIdValidator.validate("1003232979943"), .warning)
    }

    func test_letters_areInvalid() {
        XCTAssertEqual(ChatIdValidator.validate("abc"), .invalid)
    }

    func test_loneDash_isInvalid() {
        XCTAssertEqual(ChatIdValidator.validate("-"), .invalid)
    }

    func test_mixedAlphanumeric_isInvalid() {
        XCTAssertEqual(ChatIdValidator.validate("-100abc"), .invalid)
    }

    func test_saveEnabled_forValidAndWarning_disabledForInvalid() {
        XCTAssertTrue(ChatIdValidator.validate("123456").isSaveEnabled)
        XCTAssertTrue(ChatIdValidator.validate("-1003232979943").isSaveEnabled)
        XCTAssertTrue(ChatIdValidator.validate("1003232979943").isSaveEnabled)
        XCTAssertFalse(ChatIdValidator.validate("abc").isSaveEnabled)
        XCTAssertFalse(ChatIdValidator.validate("").isSaveEnabled)
    }

    func test_smallPositiveNumberMatchingShape_isValid_notWarning() {
        XCTAssertEqual(ChatIdValidator.validate("42"), .valid)
        XCTAssertEqual(ChatIdValidator.validate("999999999"), .valid)
    }

    func test_longIdsWithoutSupergroupShape_areValid() {
        XCTAssertEqual(ChatIdValidator.validate("1000000001"), .valid)
        XCTAssertEqual(ChatIdValidator.validate("7123456789"), .valid)
        XCTAssertEqual(ChatIdValidator.validate("-5564056267"), .valid)
        XCTAssertEqual(ChatIdValidator.validate("-1001234567890"), .valid)
        XCTAssertEqual(ChatIdValidator.validate("10012345678"), .valid)
    }

    func test_supergroupIdMissingMinus_warns() {
        XCTAssertEqual(ChatIdValidator.validate("1001234567890"), .warning)
        XCTAssertEqual(ChatIdValidator.validate("100123456789"), .warning)
    }

    func test_chatIdToPersist_valid_storesTrimmedValue() {
        XCTAssertEqual(TelegramDestinationView.chatIdToPersist(for: "123456"), "123456")
        XCTAssertEqual(TelegramDestinationView.chatIdToPersist(for: "  -1003232979943 "), "-1003232979943")
        XCTAssertEqual(TelegramDestinationView.chatIdToPersist(for: "1003232979943"), "1003232979943")
    }

    func test_chatIdToPersist_empty_clearsStoredValue() {
        XCTAssertNil(TelegramDestinationView.chatIdToPersist(for: ""))
        XCTAssertNil(TelegramDestinationView.chatIdToPersist(for: "   "))
    }

    func test_chatIdToPersist_invalidNonEmpty_clearsStoredValue() {
        // The stale-target bug: an invalid non-empty entry must clear the stored
        // id, not leave a previously valid one behind.
        XCTAssertNil(TelegramDestinationView.chatIdToPersist(for: "abc"))
        XCTAssertNil(TelegramDestinationView.chatIdToPersist(for: "-"))
        XCTAssertNil(TelegramDestinationView.chatIdToPersist(for: "-100abc"))
    }
}
