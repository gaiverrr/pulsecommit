import XCTest
import SwiftUI
@testable import PulseCommit

@MainActor
final class GitHubDisconnectedViewTests: XCTestCase {
    func test_onConnect_callbackIsInvoked() {
        var called = 0
        let view = GitHubDisconnectedView(onConnect: { called += 1 })
        // Drive the closure directly — the view stores the callback verbatim.
        let mirror = Mirror(reflecting: view)
        let onConnect = mirror.children.first(where: { $0.label == "onConnect" })?.value as? () -> Void
        XCTAssertNotNil(onConnect)
        onConnect?()
        onConnect?()
        XCTAssertEqual(called, 2)
    }

    func test_rationaleItems_listsRequestedScopes() {
        XCTAssertEqual(GitHubDisconnectedView.rationaleItems, [
            "Contents: read & write",
            "Metadata: read",
            "Only the repository you pick",
            "Nothing else"
        ])
    }

    func test_footnote_mentionsKeychainAndNoBackend() {
        let joined = GitHubDisconnectedView.footnoteLines.joined(separator: " ")
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("Keychain"))
        XCTAssertTrue(joined.localizedCaseInsensitiveContains("backend"))
    }

    func test_view_canBeInstantiated() {
        _ = GitHubDisconnectedView(onConnect: {})
    }
}
