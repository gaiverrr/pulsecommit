import XCTest
import HealthCore
@testable import PulseCommit

private struct StubCategory: HealthCategory {
    let id: String
    let displayName: String = "Stub"
    let samples: [any SampleDTO]

    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
        samples.filter { $0.startDate >= from && $0.startDate <= to }
    }

    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        var fragment = SummaryFragment()
        fragment.metrics["count"] = .int(samples.count)
        return fragment
    }
}

final class SnapshotPipelineTests: XCTestCase {
    private let timezone = TimeZone(identifier: "UTC")!

    private func iso(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func testProducesFileEntriesForEachDayInWindow() async throws {
        let steps = StubCategory(
            id: "steps",
            samples: [
                QuantitySampleDTO(
                    categoryID: "steps",
                    startDate: iso("2026-01-01T10:00:00Z"),
                    endDate: iso("2026-01-01T10:01:00Z"),
                    value: 100,
                    unit: "count",
                    sourceName: "iPhone",
                    sourceBundleID: "com.apple.health"
                ),
                QuantitySampleDTO(
                    categoryID: "steps",
                    startDate: iso("2026-01-02T11:00:00Z"),
                    endDate: iso("2026-01-02T11:01:00Z"),
                    value: 200,
                    unit: "count",
                    sourceName: "iPhone",
                    sourceBundleID: "com.apple.health"
                ),
            ]
        )
        let excluded = StubCategory(id: "excluded", samples: [])

        let registry = CategoryRegistry(categories: [steps, excluded])
        let pipeline = SnapshotPipeline(
            registry: registry,
            timezone: timezone,
            deviceName: "iPhone Test",
            appVersion: "1.0.0",
            clock: { self.iso("2026-01-02T23:59:59Z") }
        )

        let days = try await pipeline.run(
            from: iso("2026-01-01T00:00:00Z"),
            to: iso("2026-01-02T23:00:00Z"),
            enabledCategoryIds: ["steps"]
        )

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].snapshot.latestSampleAt, iso("2026-01-01T10:01:00Z"))
        XCTAssertEqual(days[1].snapshot.latestSampleAt, iso("2026-01-02T11:01:00Z"))
        let summaryFile = try XCTUnwrap(days[0].files.first { $0.path.hasSuffix("/summary.json") })
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: summaryFile.data) as? [String: Any])
        XCTAssertEqual(json["latest_sample_at"] as? String, "2026-01-01T10:01:00Z")
        let paths1 = days[0].files.map(\.path)
        let paths2 = days[1].files.map(\.path)
        XCTAssertTrue(paths1.contains("2026-01-01/summary.json"))
        XCTAssertTrue(paths1.contains("2026-01-01/summary.md"))
        XCTAssertTrue(paths1.contains("2026-01-01/samples/steps.json"))
        XCTAssertTrue(paths2.contains("2026-01-02/summary.json"))
        XCTAssertTrue(paths2.contains("2026-01-02/samples/steps.json"))

        XCTAssertEqual(days[0].samplesByCategory["steps"]?.count, 1)
        XCTAssertEqual(days[1].samplesByCategory["steps"]?.count, 1)
        XCTAssertNil(days[0].samplesByCategory["excluded"])
    }

    func testFiltersRegistryToEnabledIds() async throws {
        let included = StubCategory(
            id: "heartRate",
            samples: [
                QuantitySampleDTO(
                    categoryID: "heartRate",
                    startDate: iso("2026-03-01T08:00:00Z"),
                    endDate: iso("2026-03-01T08:00:00Z"),
                    value: 65,
                    unit: "count/min",
                    sourceName: "Watch",
                    sourceBundleID: "com.apple.health"
                )
            ]
        )
        let dropped = StubCategory(
            id: "sleep",
            samples: [
                QuantitySampleDTO(
                    categoryID: "sleep",
                    startDate: iso("2026-03-01T02:00:00Z"),
                    endDate: iso("2026-03-01T07:00:00Z"),
                    value: 5,
                    unit: "hr",
                    sourceName: "Watch",
                    sourceBundleID: "com.apple.health"
                )
            ]
        )
        let registry = CategoryRegistry(categories: [included, dropped])
        let pipeline = SnapshotPipeline(
            registry: registry,
            timezone: timezone,
            deviceName: "iPhone Test",
            appVersion: "1.0.0",
            clock: { self.iso("2026-03-01T23:59:59Z") }
        )

        let days = try await pipeline.run(
            from: iso("2026-03-01T00:00:00Z"),
            to: iso("2026-03-01T23:00:00Z"),
            enabledCategoryIds: ["heartRate"]
        )

        XCTAssertEqual(days.count, 1)
        let paths = days[0].files.map(\.path)
        XCTAssertTrue(paths.contains("2026-03-01/samples/heartRate.json"))
        XCTAssertFalse(paths.contains("2026-03-01/samples/sleep.json"))
        XCTAssertNotNil(days[0].samplesByCategory["heartRate"])
        XCTAssertNil(days[0].samplesByCategory["sleep"])
        XCTAssertFalse(days[0].snapshot.summaries.keys.contains("sleep"))
    }

    func test_run_emitsStartingSamplesFetchBetweenPhases() async throws {
        let fixture = SnapshotPipelineFixture.makeWithCategoryCount(2)
        let pipeline = fixture.pipeline

        let captured = ActorIsolatedEvents()
        let handler: RunProgressHandler = { event in
            await captured.append(event)
        }

        _ = try await pipeline.run(
            from: fixture.from,
            to: fixture.to,
            enabledCategoryIds: fixture.allIds,
            progress: handler
        )

        let events = await captured.events
        let summaryCount = events.filter { if case .readingSummary = $0 { return true } else { return false } }.count
        let samplesCount = events.filter { if case .readingSamples = $0 { return true } else { return false } }.count
        XCTAssertEqual(summaryCount, 2)
        XCTAssertEqual(samplesCount, 2)
        XCTAssertTrue(events.contains(.startingSamplesFetch), "bridge event must be emitted")

        // .startingSamplesFetch must appear after the last .readingSummary and before the first .readingSamples
        let bridgeIndex = try XCTUnwrap(events.firstIndex(of: .startingSamplesFetch))
        let lastSummaryIndex = try XCTUnwrap(events.lastIndex { if case .readingSummary = $0 { return true } else { return false } })
        let firstSamplesIndex = try XCTUnwrap(events.firstIndex { if case .readingSamples = $0 { return true } else { return false } })
        XCTAssertLessThan(lastSummaryIndex, bridgeIndex)
        XCTAssertLessThan(bridgeIndex, firstSamplesIndex)
    }
}

private struct SnapshotPipelineFixture {
    let pipeline: SnapshotPipeline
    let from: Date
    let to: Date
    let allIds: Set<String>

    static func makeWithCategoryCount(_ n: Int) -> SnapshotPipelineFixture {
        let cats: [any HealthCategory] = (0..<n).map { StubPipelineCategory(id: "cat\($0)") }
        let registry = CategoryRegistry(categories: cats)
        let pipeline = SnapshotPipeline(
            registry: registry,
            timezone: TimeZone(identifier: "UTC")!,
            deviceName: "iPhone-Test",
            appVersion: "1.0.0",
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        return SnapshotPipelineFixture(
            pipeline: pipeline,
            from: Date(timeIntervalSince1970: 1_700_000_000 - 86_400),
            to: Date(timeIntervalSince1970: 1_700_000_000),
            allIds: Set(cats.map(\.id))
        )
    }
}

private struct StubPipelineCategory: HealthCategory {
    let id: String
    var displayName: String { id }
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { [] }
    func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] { [] }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SummaryFragment(metrics: [:], unit: "count")
    }
}

// Note: this `actor` helper is module-private to this test target — Task 4
// (OrchestratorTests) needs its own copy. Don't share.
private actor ActorIsolatedEvents {
    private(set) var events: [RunProgress] = []
    func append(_ event: RunProgress) { events.append(event) }
}
