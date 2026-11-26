#if DEBUG
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class MarketingDemoTests: XCTestCase {
    func test_isRequested_onlyWithLaunchArgument() {
        XCTAssertTrue(MarketingDemo.isRequested(arguments: ["PulseCommit", "-marketingDemo"]))
        XCTAssertFalse(MarketingDemo.isRequested(arguments: ["PulseCommit"]))
        XCTAssertFalse(MarketingDemo.isRequested(arguments: ["PulseCommit", "-marketingDemoX"]))
    }

    func test_container_hasBothDestinationsConfigured() async {
        let container = MarketingDemo.makeContainer(stepDelay: .zero)
        let ids = await IntentRunner.configuredSinkIds(container)
        XCTAssertEqual(ids, ["github", "telegram"])
    }

    func test_container_seedsSuccessfulHistory() throws {
        let container = MarketingDemo.makeContainer(stepDelay: .zero)
        let entries = try container.history.recentEntries(limit: 50)
        XCTAssertEqual(entries.count, MarketingDemo.seededDayCount)
        XCTAssertTrue(entries.allSatisfy { $0.status == .success })
        XCTAssertTrue(entries.allSatisfy { $0.githubCommitSha?.count == 40 })
    }

    func test_export_succeedsAndAppendsCommit() async throws {
        let container = MarketingDemo.makeContainer(stepDelay: .zero)
        let viewModel = HomeViewModel(container: container)
        await viewModel.runExport()
        guard case .done = viewModel.phase else {
            return XCTFail("expected done, got \(viewModel.phase)")
        }
        let entries = try container.history.recentEntries(limit: 50)
        XCTAssertEqual(entries.count, MarketingDemo.seededDayCount + 1)
        XCTAssertEqual(Set(entries.first?.sinks ?? []), ["github", "telegram"])
        XCTAssertNotNil(entries.first?.githubCommitSha)
    }

    func test_livePreview_showsDemoNumbers() async {
        let container = MarketingDemo.makeContainer(stepDelay: .zero)
        let preview = HomeLivePreviewModel(registry: container.registry)
        await preview.refresh(mode: .today)
        XCTAssertEqual(preview.todaySteps, MarketingDemo.steps)
        XCTAssertEqual(preview.todaySleepMinutes, MarketingDemo.sleepMinutes)
        XCTAssertEqual(preview.todayWorkoutCount, 1)
        XCTAssertNotNil(preview.todayActiveKcal)
    }

    func test_demoSeam_isCompiledOnlyInDebug() throws {
        let demo = try loadSource("PulseCommit/Marketing/MarketingDemo.swift")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(demo.hasPrefix("#if DEBUG"))
        XCTAssertTrue(demo.hasSuffix("#endif"))
        let composition = try loadSource("PulseCommit/Composition/AppContainer+default.swift")
        let seam = try XCTUnwrap(composition.range(of: "MarketingDemo."))
        let before = composition[..<seam.lowerBound]
        let debugOpen = try XCTUnwrap(before.range(of: "#if DEBUG", options: .backwards))
        XCTAssertNil(before[debugOpen.upperBound...].range(of: "#endif"))
    }

    private func loadSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
#endif
