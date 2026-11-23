import XCTest
@testable import PulseCommit

final class AccessibilityAuditTests: XCTestCase {
    func test_categoryRowToggle_hasAccessibilityLabel() throws {
        let source = try loadSource(relativePath: "PulseCommit/UI/Categories/CategoryRowView.swift")
        XCTAssertTrue(
            source.contains("accessibilityLabel"),
            "Toggle(\"\").labelsHidden() reads as a bare 'switch' to VoiceOver; it must carry the category display name"
        )
    }

    func test_pcToggle_supportsAccessibilityLabelForEmptyTitle() throws {
        let source = try loadSource(relativePath: "PulseCommit/DesignSystem/PCToggle.swift")
        XCTAssertTrue(
            source.contains("accessibilityLabel"),
            "PCToggle with an empty title is an unlabeled switch for VoiceOver"
        )
    }

    func test_emptyTitlePCToggleCallSites_passAccessibilityLabel() throws {
        for path in [
            "PulseCommit/UI/Destinations/DestinationsView.swift",
        ] {
            let source = try loadSource(relativePath: path)
            XCTAssertTrue(
                source.contains("accessibilityLabel:"),
                "\(path): empty-title PCToggle call sites must pass accessibilityLabel"
            )
        }
    }

    func test_pcSegmented_exposesSelectionToVoiceOver() throws {
        let source = try loadSource(relativePath: "PulseCommit/DesignSystem/PCSegmented.swift")
        XCTAssertTrue(
            source.contains(".isSelected"),
            "The accent-filled selection is purely visual; VoiceOver needs the .isSelected trait"
        )
    }

    private func loadSource(relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
