import XCTest
@testable import PulseCommit

final class HomeContainerViewSourceTests: XCTestCase {
    func test_homeView_offersEveryPeriodWithoutLockOrRunCounter() throws {
        let source = try loadSource(relativePath: "PulseCommit/UI/Home/HomeView.swift")
        for period in ["today", "yesterday", "last7Days", "last30Days"] {
            XCTAssertTrue(source.contains(".tag(HomeViewModel.Period.\(period))"), period)
        }
        XCTAssertFalse(source.contains("lock.fill"))
        XCTAssertFalse(source.contains("RUNS"))
        XCTAssertFalse(source.contains("PRO"))
    }

    func test_homeView_doesNotOfferCustomRangeUntilDatePickerExists() throws {
        let source = try loadSource(relativePath: "PulseCommit/UI/Home/HomeView.swift")
        XCTAssertFalse(
            source.contains("Custom range"),
            "Period.custom silently aliases .todayLive — offering it (picker tag or locked teaser) sells a feature that exports today only; Shortcuts BackfillRange is the custom-range path until a date-picker sheet ships"
        )
        XCTAssertFalse(
            source.contains("chip(for: .custom"),
            "The chip row must not show a ghost 'custom' chip that no menu item can ever select"
        )
        XCTAssertTrue(
            source.contains("chip(for: .last30Days"),
            "The chip row should mirror the menu options: today / yesterday / 7d / 30d"
        )
    }

    func test_settingsVersion_readsBundleNotLiteral() throws {
        let source = try loadSource(relativePath: "PulseCommit/UI/Settings/SettingsView.swift")
        XCTAssertFalse(
            source.contains("\"1.0.0\"") || source.contains("\"v1.0.0\""),
            "Settings hard-codes 1.0.0 while the bundle ships MARKETING_VERSION 1.0 — Home and Settings disagree on screen; read CFBundleShortVersionString"
        )
        XCTAssertTrue(source.contains("CFBundleShortVersionString"))
    }

    private func loadSource(relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
