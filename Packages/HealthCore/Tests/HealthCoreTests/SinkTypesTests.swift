import XCTest
@testable import HealthCore

final class SinkTypesTests: XCTestCase {
    func test_FileEntry_valueEquality() {
        let a = FileEntry(path: "summary.json", data: Data("{}".utf8))
        let b = FileEntry(path: "summary.json", data: Data("{}".utf8))
        let c = FileEntry(path: "summary.json", data: Data("{\"x\":1}".utf8))
        let d = FileEntry(path: "other.json", data: Data("{}".utf8))
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
        XCTAssertNotEqual(a, d)
    }

    func test_SinkResult_successPatternMatching() {
        let url = URL(string: "https://github.com/owner/repo/commit/abc123")!
        let result: SinkResult = .success(reference: "abc123", url: url)

        switch result {
        case .success(let reference, let resolvedURL):
            XCTAssertEqual(reference, "abc123")
            XCTAssertEqual(resolvedURL, url)
        }
    }

    func test_SinkResult_successWithoutURL() {
        let result: SinkResult = .success(reference: "deadbeef", url: nil)
        if case .success(let reference, let resolvedURL) = result {
            XCTAssertEqual(reference, "deadbeef")
            XCTAssertNil(resolvedURL)
        } else {
            XCTFail("expected .success")
        }
    }
}
