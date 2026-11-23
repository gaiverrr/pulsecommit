import SwiftUI
import UIKit
import XCTest
@testable import PulseCommit

@MainActor
final class AutomaticWorkoutRenderTests: XCTestCase {
    func test_renderAutomaticWorkoutStatesAndDisclosureAt375Points() throws {
        let workoutID = UUID(uuidString: "00000000-0000-0000-0000-000000000040")!
        let states: [(String, Bool, AutomaticWorkoutCardState)] = [
            ("off", false, .off),
            ("on", true, .on),
            ("blocked", true, .blocked("Background registration failed — open the app to retry")),
            ("unknown", true, .deliveryUnknown(workoutID))
        ]

        for (name, isOn, state) in states {
            let view = ScrollView {
                AutomaticWorkoutDeliveryCard(
                    isOn: isOn,
                    state: state,
                    onToggle: { _ in },
                    onRetry: { _ in }
                )
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            try render(view, name: "automatic-workout-\(name)-375x812")
        }

        let scope = AutomaticWorkoutConsentScope(
            chatID: "-1001234567890",
            messageThreadID: 42,
            botToken: "synthetic-token"
        )
        try render(
            AutomaticWorkoutConsentSheet(scope: scope, onAllow: {}, onDecline: {}),
            name: "automatic-workout-disclosure-375x812"
        )
        try render(
            AutomaticWorkoutConsentSheet(scope: scope, onAllow: {}, onDecline: {})
                .environment(\.dynamicTypeSize, .accessibility1),
            name: "automatic-workout-disclosure-accessibility-375x812"
        )
    }

    private func render<V: View>(_ view: V, name: String) throws {
        let frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: frame)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = frame
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: frame.size)
        let image = renderer.image { _ in host.view.drawHierarchy(in: frame, afterScreenUpdates: true) }
        let png = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(png.count, 10_000)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputDirectory = ProcessInfo.processInfo.environment["PULSECOMMIT_RENDER_OUTPUT_DIR"] {
            let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
        }
        window.isHidden = true
    }
}
