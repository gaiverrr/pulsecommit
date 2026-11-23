import SwiftUI
import UIKit
import XCTest
@testable import PulseCommit

@MainActor
final class ConsentSheetRenderTests: XCTestCase {
    func test_renderActualDisclosureForBothDestinationsAndLargerText() throws {
        let scopes: [(String, HealthExportConsentScope)] = [
            ("github", HealthExportConsentScope(
                destination: .github(owner: "octocat", repo: "health", branch: "main", subdir: "exports"),
                enabledCategoryIds: ["steps", "sleep", "workouts"]
            )),
            ("telegram", HealthExportConsentScope(
                destination: .telegram(chatID: "-1001234567890", messageThreadID: 42),
                enabledCategoryIds: ["steps", "sleep", "workouts"]
            ))
        ]

        for (name, scope) in scopes {
            for (sizeName, dynamicType) in [
                ("standard", DynamicTypeSize.large),
                ("larger-text", DynamicTypeSize.accessibility1)
            ] {
                let view = HealthExportConsentSheet(scope: scope, onAllow: {}, onDecline: {})
                    .environment(\.dynamicTypeSize, dynamicType)
                let host = UIHostingController(rootView: view)
                let frame = CGRect(x: 0, y: 0, width: 375, height: 812)
                let window = UIWindow(frame: frame)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.frame = frame
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()

                let renderer = UIGraphicsImageRenderer(size: frame.size)
                let image = renderer.image { _ in
                    host.view.drawHierarchy(in: frame, afterScreenUpdates: true)
                }
                let png = try XCTUnwrap(image.pngData())
                XCTAssertGreaterThan(png.count, 10_000)
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "consent-\(name)-\(sizeName)-375x812"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.isHidden = true
            }
        }
    }
}
