import XCTest
@testable import HealthCore

private struct FailingCredentialProvider: GitHubCredentialProvider {
    let owner: String
    let repo: String
    let branch: String
    let subdir: String
    let error: GitHubAuthError

    func accessToken() async throws -> String {
        throw error
    }
}

final class GitHubSinkSessionExpiredTests: XCTestCase {
    override func setUp() {
        super.setUp()
        GitHubMockTransport.register()
    }

    override func tearDown() {
        GitHubMockTransport.unregister()
        super.tearDown()
    }

    func testSessionExpiredPropagatesAndMakesNoAPICalls() async {
        let provider = FailingCredentialProvider(
            owner: "alice",
            repo: "health",
            branch: "main",
            subdir: "",
            error: .sessionExpired
        )
        let sink = GitHubSink(credentialProvider: provider, session: .shared)
        let snapshot = DailySnapshot(
            date: SampleFixtures.iso("2026-05-14T00:00:00Z"),
            timezone: "UTC",
            generatedAt: SampleFixtures.iso("2026-05-14T22:30:12Z"),
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )

        do {
            _ = try await sink.deliver(snapshot: snapshot, files: [])
            XCTFail("expected sessionExpired to throw")
        } catch let error as GitHubAuthError {
            XCTAssertEqual(error, .sessionExpired)
        } catch {
            XCTFail("unexpected error type: \(error)")
        }

        XCTAssertEqual(GitHubMockTransport.captured.count, 0)
    }
}
