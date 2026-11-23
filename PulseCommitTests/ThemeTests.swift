import SwiftUI
import XCTest
@testable import PulseCommit

@MainActor
final class ThemeTests: XCTestCase {
    func test_accentHexConstantMatchesLockedLime() {
        XCTAssertEqual(Theme.Hex.accent, 0xA4F03A)
    }

    func test_pcStatTileFontTokenExists() {
        // pc-3gw: stat-tile values must use monospaced design per the design tokens in AGENTS.md
        // typography rule. Token presence guards against accidental regression
        // to .rounded or another non-mono design.
        XCTAssertEqual(Font.pcStatTile, Font.system(size: 36, weight: .semibold, design: .monospaced))
    }

    func test_accentColorResolvesToExpectedSRGBComponents() throws {
        let resolved = Theme.accent.resolve(in: EnvironmentValues())
        XCTAssertEqual(Double(resolved.red), 0xA4 / 255.0, accuracy: 0.01)
        XCTAssertEqual(Double(resolved.green), 0xF0 / 255.0, accuracy: 0.01)
        XCTAssertEqual(Double(resolved.blue), 0x3A / 255.0, accuracy: 0.01)
    }
}
