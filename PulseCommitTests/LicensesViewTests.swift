import XCTest
import SwiftUI
@testable import PulseCommit

@MainActor
final class LicensesViewTests: XCTestCase {
    func test_zipFoundationLicense_containsAttribution() {
        let text = LicensesView.zipFoundationLicense
        XCTAssertTrue(text.contains("MIT"))
        XCTAssertTrue(text.contains("Permission is hereby granted"))
    }

    func test_zipFoundationLicense_containsAsIsWarrantyDisclaimer() {
        let text = LicensesView.zipFoundationLicense
        XCTAssertTrue(text.localizedCaseInsensitiveContains("AS IS"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("WITHOUT WARRANTY"))
    }

    func test_view_canBeInstantiated() {
        _ = LicensesView()
    }
}
