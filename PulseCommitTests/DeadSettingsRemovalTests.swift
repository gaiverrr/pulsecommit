import XCTest
@testable import PulseCommit

/// v1.0 decision (2026-06-10): the Units toggle and the Backfill-window
/// setting were write-only — no export path read them. Dead controls that
/// promise behavior are worse than no controls; both return only when an
/// export path actually consumes them.
final class DeadSettingsRemovalTests: XCTestCase {
    func test_settingsScreen_hasNoDeadControls() throws {
        let source = try loadSource(relativePath: "PulseCommit/UI/Settings/SettingsView.swift")
        XCTAssertFalse(source.contains("Backfill window"), "write-only setting must not ship")
        XCTAssertFalse(source.contains("\"Units\""), "exports are metric by schema design; the toggle did nothing")
        XCTAssertFalse(source.contains("BackfillSettingsView"))
    }

    func test_backfillSettingsScreen_isDeleted() {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        let path = root.appendingPathComponent("PulseCommit/UI/Settings/BackfillSettingsView.swift").path
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func test_preferencesStore_hasNoDeadAccessors() throws {
        let source = try loadSource(relativePath: "PulseCommit/Persistence/PreferencesStore.swift")
        XCTAssertFalse(source.contains("var unitSystem"))
        XCTAssertFalse(source.contains("var backfillWindowDays"))
        XCTAssertFalse(source.contains("enum UnitSystem"))
    }

    private func loadSource(relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
