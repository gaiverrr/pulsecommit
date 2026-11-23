import XCTest
import HealthCore
@testable import PulseCommit

private struct EmptyCategory: HealthCategory {
    let id: String
    let displayName: String
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { [] }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SummaryFragment(metrics: [:], unit: "count")
    }
}

final class EndToEndPipelineTests: XCTestCase {
    func test_normalizerProducesOneSnapshotPerDayWithSchemaVersion() async throws {
        let registry = CategoryRegistry(categories: [
            EmptyCategory(id: "steps", displayName: "Steps"),
            EmptyCategory(id: "heart_rate", displayName: "Heart Rate")
        ])
        let tz = TimeZone(identifier: "UTC")!
        let generatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let normalizer = Normalizer(
            registry: registry,
            timezone: tz,
            deviceName: "iPhone 15",
            appVersion: "1.0.0",
            clock: { generatedAt }
        )

        let from = Date(timeIntervalSince1970: 1_699_920_000) // 2023-11-14 00:00 UTC
        let to = Date(timeIntervalSince1970: 1_700_179_200)   // 2023-11-17 00:00 UTC

        let snapshots = try await normalizer.snapshots(from: from, to: to)

        XCTAssertEqual(snapshots.count, 3)
        for snapshot in snapshots {
            XCTAssertEqual(snapshot.schemaVersion, SchemaVersion.current)
            // TimeZone(identifier: "UTC").identifier normalizes to "GMT" on iOS at runtime.
            XCTAssertEqual(snapshot.timezone, "GMT")
            XCTAssertEqual(snapshot.generatedAt, generatedAt)
            XCTAssertEqual(snapshot.deviceName, "iPhone 15")
            XCTAssertEqual(snapshot.appVersion, "1.0.0")
            XCTAssertTrue(snapshot.summaries.isEmpty)
            XCTAssertTrue(snapshot.workouts.isEmpty)
            XCTAssertTrue(snapshot.stateOfMind.isEmpty)
        }
    }

    func test_defaultRegistryComposesWithFakeHealthStore() {
        let store = FakeHealthStore()
        let registry = DefaultRegistryFactory.make(store: store)
        XCTAssertEqual(registry.all.count, 15)
        XCTAssertNotNil(registry.category(withId: "steps"))
        XCTAssertNotNil(registry.category(withId: "nutrition"))
    }
}
