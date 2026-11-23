import SwiftUI
import UIKit
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class TelegramSetupRenderTests: XCTestCase {
    func test_renderActualHomeChoiceAndTelegramSetupAt375Points() throws {
        let model = HomeViewModel(
            runRequest: { _, _ in .success },
            enabledCategoryIds: { [] },
            enabledSinkIds: { [] }
        )
        let home = HomeView(
            viewModel: model,
            deviceName: "iPhone",
            appVersion: "1.0",
            timezoneAbbreviation: "UTC",
            healthPermissionRequestCompleted: true
        )
        try attach(home, name: "home-choose-one-destination-375x812")

        let defaults = UserDefaults(suiteName: "TelegramSetupRenderTests.\(UUID().uuidString)")!
        let healthStore = HealthStoreClient()
        let container = AppContainer(
            secrets: InMemorySecretsStore(),
            preferences: PreferencesStore(defaults: defaults),
            history: HistoryStore.noOp(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            orchestratorFactory: { _ in fatalError("No export in render test") }
        )
        let telegram = NavigationStack {
            TelegramDestinationView().environmentObject(container)
        }
        try attach(telegram, name: "telegram-setup-375x812")
        try attach(telegram.environment(\.dynamicTypeSize, .accessibility1),
                   name: "telegram-setup-larger-text-375x812")
    }

    private func attach<V: View>(_ view: V, name: String) throws {
        let frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        let host = UIHostingController(rootView: view)
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
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.isHidden = true
    }
}
