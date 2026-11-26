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
        width: CGFloat = 335,
        dynamicType: DynamicTypeSize = .large,
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
        let root = view.bigButton
            .environment(\.dynamicTypeSize, dynamicType)
            .frame(width: width)
            .onPreferenceChange(BigButtonDividerMinYKey.self) { box.dividerMinY = $0 }
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

    private let longReason = "GitHub: credential refresh failed with HTTP 401 incorrect_client_credentials while preparing the commit for the selected repository"

    private func assertPhasesMatchIdle(width: CGFloat, dynamicType: DynamicTypeSize, file: StaticString = #filePath, line: UInt = #line) {
        let baseline = measure(phase: .idle, width: width, dynamicType: dynamicType, file: file, line: line)
        let cases: [(String, Measurement)] = [
            ("running", measure(phase: .running, stage: ("> samples · ", "heart_rate_variability", "8/14"), width: width, dynamicType: dynamicType, file: file, line: line)),
            ("done", measure(phase: .done(at: Date()), width: width, dynamicType: dynamicType, file: file, line: line)),
            ("error", measure(phase: .error(reason: "HTTP 401"), width: width, dynamicType: dynamicType, file: file, line: line)),
            ("error, long reason", measure(phase: .error(reason: longReason), width: width, dynamicType: dynamicType, file: file, line: line))
        ]
        for (name, measurement) in cases {
            XCTAssertEqual(measurement.dividerMinY, baseline.dividerMinY, accuracy: 0.5, "divider y in \(name) at \(width)/\(dynamicType)", file: file, line: line)
            XCTAssertEqual(measurement.height, baseline.height, accuracy: 0.5, "height in \(name) at \(width)/\(dynamicType)", file: file, line: line)
        }
    }

    private func assertTitleFits(width: CGFloat, dynamicType: DynamicTypeSize, file: StaticString = #filePath, line: UInt = #line) {
        let font = UIFont.systemFont(ofSize: 36, weight: .bold)
        let contentWidth = width - 40
        for title in ["Export Now", "Retry Export", "Committing…"] {
            let natural = (title as NSString).size(withAttributes: [.font: font]).width
            XCTAssertLessThanOrEqual(natural * 0.7, contentWidth, "\(title) clipped at \(width)/\(dynamicType)", file: file, line: line)
        }
    }

    func test_dividerAndHeight_matchIdle_at320pt() {
        assertPhasesMatchIdle(width: 320, dynamicType: .large)
        assertTitleFits(width: 320, dynamicType: .large)
    }

    func test_dividerAndHeight_matchIdle_atAccessibility3() {
        assertPhasesMatchIdle(width: 335, dynamicType: .accessibility3)
        assertTitleFits(width: 335, dynamicType: .accessibility3)
    }

    func test_dividerAndHeight_matchIdle_at320ptAccessibility3() {
        assertPhasesMatchIdle(width: 320, dynamicType: .accessibility3)
    }
}
