import SwiftUI
import UIKit
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class HomeBigButtonPhaseLayoutTests: XCTestCase {
    private struct Measurement: Equatable {
        var dividerMinY: CGFloat
        var height: CGFloat
    }

    private final class Box {
        var dividerMinY: CGFloat = -1
    }

    private func measure(
        phase: HomeViewModel.Phase,
        stage: (prefix: String, label: String?, counter: String?) = ("", nil, nil),
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Measurement {
        let viewModel = HomeViewModelTests.makeViewModel(phase: phase)
        viewModel.stagePrefix = stage.prefix
        viewModel.stageLabel = stage.label
        viewModel.stageCounter = stage.counter
        let livePreview = HomeLivePreviewModel(registry: CategoryRegistry(categories: []))
        livePreview.todaySteps = 12_483
        let view = HomeView(
            viewModel: viewModel,
            livePreview: livePreview,
            deviceName: "iPhone 18 Pro",
            appVersion: "1.0.2",
            timezoneAbbreviation: "UTC",
            githubConfigured: true
        )
        let box = Box()
        let width: CGFloat = 335
        let root = view.bigButton
            .frame(width: width)
            .onPreferenceChange(BigButtonDividerMinYKey.self) { box.dividerMinY = $0 }
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 375, height: 812))
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
        while box.dividerMinY < 0 && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.view.layoutIfNeeded()
        }
        window.isHidden = true
        XCTAssertGreaterThan(box.dividerMinY, 0, "divider did not report its position", file: file, line: line)
        return Measurement(dividerMinY: box.dividerMinY, height: size.height)
    }

    func test_dividerAndHeight_areIdenticalAcrossPhases() {
        let cases: [(String, Measurement)] = [
            ("idle", measure(phase: .idle)),
            ("running, no stage yet", measure(phase: .running)),
            ("running", measure(
                phase: .running,
                stage: ("> samples · ", "heart_rate_variability", "8/14")
            )),
            ("done", measure(phase: .done(at: Date()))),
            ("error", measure(phase: .error(reason: "HTTP 401"))),
            ("error, long reason", measure(
                phase: .error(reason: "GitHub: credential refresh failed with HTTP 401 incorrect_client_credentials while preparing the commit for the selected repository")
            ))
        ]
        let baseline = cases[0].1
        for (name, measurement) in cases.dropFirst() {
            XCTAssertEqual(
                measurement.dividerMinY, baseline.dividerMinY, accuracy: 0.5,
                "divider y in \(name) is \(measurement.dividerMinY), idle is \(baseline.dividerMinY)"
            )
            XCTAssertEqual(
                measurement.height, baseline.height, accuracy: 0.5,
                "big button height in \(name) is \(measurement.height), idle is \(baseline.height)"
            )
        }
    }
}
