import SwiftUI
import UIKit
import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class WebhookScreenRenderTests: XCTestCase {
    private let endpoint = "https://hooks.example.com/pulse"
    private let sampleToken = "pc_demo_9f2c41b7e05a4d18b3c6"

    private func ephemeralDefaults() -> UserDefaults {
        let suite = "WebhookScreenRenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeContainer(consented: Bool) async throws -> AppContainer {
        let defaults = ephemeralDefaults()
        let preferences = PreferencesStore(defaults: defaults)
        let healthStore = HealthStoreClient()
        let container = AppContainer(
            secrets: InMemorySecretsStore(),
            preferences: preferences,
            history: try HistoryStore.inMemory(),
            healthStore: healthStore,
            registry: DefaultRegistryFactory.make(store: healthStore),
            consentStore: HealthExportConsentStore(defaults: defaults),
            automaticWorkoutConsentStore: AutomaticWorkoutConsentStore(defaults: defaults),
            orchestratorFactory: AppContainer.defaultOrchestratorFactory(runGate: ExportRunGate(), healthStore: healthStore)
        )
        container.preferences.enabledCategoryIds = ["steps", "sleep", "heart_rate"]
        try await container.saveWebhookSettings(endpoint: endpoint, token: sampleToken, tokenHeader: "Authorization")
        if consented, let scope = await container.currentConsentScope(for: .webhook) {
            _ = await container.acceptConsentIfCurrent(scope)
        }
        return container
    }

    func test_renderWebhookScreens() async throws {
        let consented = try await makeContainer(consented: true)
        let unconsented = try await makeContainer(consented: false)
        let maybeScope = await unconsented.currentConsentScope(for: .webhook)
        let scope = try XCTUnwrap(maybeScope)

        try await capture("01-destinations", NavigationStack {
            DestinationsView(path: .constant([]))
        }.environmentObject(consented))

        try await capture("02-webhook-with-token", NavigationStack {
            WebhookDestinationView(
                initialDraft: WebhookSettingsDraft(endpoint: endpoint, token: sampleToken, tokenHeader: "Authorization"),
                initialTestStatus: .delivered(host: "hooks.example.com", statusCode: 200),
                sendTest: { _, _ in 200 }
            )
        }.environmentObject(consented))

        try await capture("03-webhook-without-token", NavigationStack {
            WebhookDestinationView(
                initialDraft: WebhookSettingsDraft(endpoint: endpoint, token: "", tokenHeader: "Authorization"),
                sendTest: { _, _ in 200 }
            )
        }.environmentObject(unconsented))

        try await capture("04-consent-sheet", HealthExportConsentSheet(scope: scope, onAllow: {}, onDecline: {}))

        let now = Date()
        let rows = [
            HistoryRowModel.from(snapshot: HistoryEntrySnapshot(
                id: UUID(),
                startedAt: now.addingTimeInterval(-600),
                finishedAt: now.addingTimeInterval(-590),
                status: .success,
                sinks: ["webhook"],
                daysCovered: ["2026-11-25"],
                webhookReference: WebhookDestinationSink.reference(host: "hooks.example.com", statusCode: 200)
            ), now: now),
            HistoryRowModel.from(snapshot: HistoryEntrySnapshot(
                id: UUID(),
                startedAt: now.addingTimeInterval(-86_400),
                finishedAt: now.addingTimeInterval(-86_390),
                status: .failed,
                sinks: ["webhook"],
                daysCovered: ["2026-11-24"],
                errorMessage: "sink failed: " + WebhookDeliveryError(
                    host: "hooks.example.com",
                    reason: WebhookSinkError.httpStatus(401).localizedDescription
                ).localizedDescription
            ), now: now)
        ]
        try await capture("05-history", NavigationStack {
            HistoryView(rows: rows, totalCommits: 1, totalFailures: 1, sinceLabel: "2026-11-24")
        })
    }

    private func capture<V: View>(_ name: String, _ view: V) async throws {
        let frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: view.preferredColorScheme(.dark))
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: frame)
        }
        window.windowLevel = .alert + 1
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(nanoseconds: 700_000_000)

        let bounds = window.bounds
        let image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            host.view.drawHierarchy(in: bounds, afterScreenUpdates: true)
        }
        let png = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(png.count, 10_000)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "webhook-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        guard let directory = ProcessInfo.processInfo.environment["PC_SCREENSHOT_DIR"] else { return }
        let base = URL(fileURLWithPath: directory)
        let request = base.appendingPathComponent("\(name).request")
        let done = base.appendingPathComponent("\(name).done")
        try Data().write(to: request)
        for _ in 0..<150 where !FileManager.default.fileExists(atPath: done.path) {
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
}
