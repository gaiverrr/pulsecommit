import SwiftUI
import UIKit
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class HomeBigButtonHitAreaTests: XCTestCase {
    private final class Box {
        var areas: [String: CGRect] = [:]
    }

    private func measureErrorPhase(reason: String, width: CGFloat) -> [String: CGRect] {
        let viewModel = HomeViewModelTests.makeViewModel(phase: .error(reason: reason, entryId: UUID()))
        let livePreview = HomeLivePreviewModel(registry: CategoryRegistry(categories: []))
        let view = HomeView(
            viewModel: viewModel,
            livePreview: livePreview,
            deviceName: "iPhone 18 Pro",
            appVersion: "1.0.2",
            timezoneAbbreviation: "UTC",
            githubConfigured: true
        )
        let box = Box()
        let root = view.bigButton
            .frame(width: width)
            .onPreferenceChange(BigButtonHitAreasKey.self) { box.areas = $0 }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: max(width, 320), height: 812))
        window.rootViewController = host
        window.makeKeyAndVisible()
        let size = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        _ = UIGraphicsImageRenderer(size: size).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        let deadline = Date().addingTimeInterval(2)
        while box.areas["subLabelHitArea"] == nil && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.view.layoutIfNeeded()
        }
        window.isHidden = true
        return box.areas
    }

    private let longReason = "GitHub: credential refresh failed with HTTP 401 incorrect_client_credentials while preparing the commit for the selected repository"

    func test_errorPhase_buttonCentreRetriesAndOnlySubLabelOpensRunDetails() throws {
        for width: CGFloat in [335, 320] {
            for reason in ["HTTP 401", longReason] {
                let label = "width \(width), reason \(reason.prefix(12))"
                let areas = measureErrorPhase(reason: reason, width: width)
                let export = try XCTUnwrap(areas["exportButton"], label)
                let text = try XCTUnwrap(areas["subLabelText"], label)
                let hit = try XCTUnwrap(areas["subLabelHitArea"], "overlay did not render: \(label)")

                XCTAssertFalse(hit.contains(CGPoint(x: export.midX, y: export.midY)), "button centre opens Run details: \(label)")
                XCTAssertGreaterThanOrEqual(hit.minY, text.minY - 0.5, "hit area reaches above the sub-label: \(label)")
                XCTAssertTrue(hit.contains(CGPoint(x: text.midX, y: text.midY)), "sub-label centre not tappable: \(label)")
                XCTAssertLessThanOrEqual(hit.maxY, export.maxY + 0.5, "hit area leaves the button: \(label)")
                XCTAssertGreaterThanOrEqual(hit.height, 44, "hit area below 44 pt: \(label)")
            }
        }
    }
}
