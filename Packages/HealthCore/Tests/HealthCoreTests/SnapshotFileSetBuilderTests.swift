import XCTest
@testable import HealthCore

final class SnapshotFileSetBuilderTests: XCTestCase {
    private func makeSnapshot() -> DailySnapshot {
        let date = SampleFixtures.iso("2026-05-14T00:00:00Z")
        let generated = SampleFixtures.iso("2026-05-14T22:30:12Z")
        var snap = DailySnapshot(
            date: date,
            timezone: "UTC",
            generatedAt: generated,
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = [
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count")
        ]
        snap.workouts = [
            WorkoutDTO(
                id: "7f3a",
                type: .outdoorRun,
                startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
                endDate: SampleFixtures.iso("2026-05-14T07:38:00Z"),
                durationMinutes: 38,
                distanceKm: 6.2,
                activeEnergyKcal: 410,
                avgHeartRate: 152,
                maxHeartRate: 174,
                route: [
                    RoutePointDTO(
                        time: SampleFixtures.iso("2026-05-14T07:00:00Z"),
                        latitude: 38.7, longitude: -9.1, elevationMeters: 12
                    )
                ]
            )
        ]
        return snap
    }

    func testProducesExpectedPathsPrefixedByDayKey() throws {
        let snapshot = makeSnapshot()
        let samples: [String: [any SampleDTO]] = [
            "steps": [
                SampleFixtures.quantity(
                    categoryID: "steps",
                    start: "2026-05-14T09:00:00Z",
                    value: 250
                )
            ]
        ]
        let files = try SnapshotFileSetBuilder().build(
            snapshot: snapshot,
            samplesByCategory: samples
        )
        let paths = files.map(\.path).sorted()
        XCTAssertEqual(paths, [
            "2026-05-14/routes/7f3a-outdoor-run.gpx",
            "2026-05-14/samples/steps.json",
            "2026-05-14/summary.json",
            "2026-05-14/summary.md",
            "2026-05-14/workouts/7f3a-outdoor-run.json"
        ])
    }

    func testEverythingIsPrefixedByDayKey() throws {
        let files = try SnapshotFileSetBuilder().build(snapshot: makeSnapshot())
        XCTAssertFalse(files.isEmpty)
        for file in files {
            XCTAssertTrue(file.path.hasPrefix("2026-05-14/"), "unexpected path: \(file.path)")
        }
    }

    func testSummaryMarkdownIsUTF8Encoded() throws {
        let files = try SnapshotFileSetBuilder().build(snapshot: makeSnapshot())
        let md = try XCTUnwrap(files.first { $0.path == "2026-05-14/summary.md" })
        let text = try XCTUnwrap(String(data: md.data, encoding: .utf8))
        XCTAssertTrue(text.contains("Pulse Commit · 2026-05-14"))
    }
}
