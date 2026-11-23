import XCTest
@testable import HealthCore

final class TemperatureAndZonesRenderingTests: XCTestCase {
    private func snapshot() -> DailySnapshot {
        DailySnapshot(date: SampleFixtures.iso("2026-05-14T00:00:00Z"), timezone: "Europe/Lisbon",
            generatedAt: SampleFixtures.iso("2026-05-14T20:00:00Z"), deviceName: "Test", appVersion: "1.0")
    }
    private func workout() -> WorkoutDTO {
        let start = snapshot().date
        let rate = QuantitySampleDTO(categoryID: "heart_rate", startDate: start, endDate: start,
            value: 110, unit: "count/min", sourceName: "Watch", sourceBundleID: "watch")
        let interval = DateInterval(start: start, duration: 60)
        let zones = HeartRateZoneEstimator.estimate(samples: [rate],
            configuration: HeartRateZoneConfiguration(lowerBoundsBPM: [100, 120, 140, 160])!,
            workout: interval, activeIntervals: [interval])
        return WorkoutDTO(id: "test", type: .outdoorRun, startDate: start, endDate: interval.end,
            durationMinutes: 1, distanceKm: nil, activeEnergyKcal: nil, avgHeartRate: 110, maxHeartRate: 110,
            route: [], heartRateZones: zones)
    }
    func test_telegramLabelsBaselineMethodAndCustomEstimatedZones() {
        var snap = snapshot()
        snap.summaries["wrist_temperature"] = SummaryFragment(metrics: [
            "avg_c": .double(36.3), "baseline_c": .double(36), "deviation_c": .double(0.3), "baseline_nights": .int(7)
        ], unit: "degC")
        snap.workouts = [workout()]
        for verbosity in [SummaryVerbosity.standard, .verbose] {
            let md = SummaryMarkdownSerializer().serialize(snap, verbosity: verbosity, flavor: .telegramV2)
            XCTAssertTrue(md.contains("+0.30 °C"))
            XCTAssertTrue(md.contains("PulseCommit: 36.00 °C · 7 nights / 28d"))
            XCTAssertTrue(md.contains("HR zones (custom, estimated)"))
            XCTAssertTrue(md.contains("Z2 100-119 bpm: 0:30"))
            XCTAssertTrue(md.contains("HR coverage: 0:30 / 1:00 active"))
        }
    }
    func test_githubLabelsCustomEstimatedZonesAndCoverage() {
        var snap = snapshot()
        snap.workouts = [workout()]

        let md = SummaryMarkdownSerializer().serialize(snap, flavor: .github)

        XCTAssertTrue(md.contains("Time (Europe/Lisbon): 01:00–01:01"), md)
        XCTAssertTrue(md.contains("HR zones (custom, estimated)"), md)
        XCTAssertTrue(md.contains("HR coverage: 0:30 / 1:00 active"), md)
    }
    func test_insufficientTemperatureHistoryShowsProgressWithoutDelta() {
        var snap = snapshot()
        snap.summaries["wrist_temperature"] = SummaryFragment(metrics: ["avg_c": .double(36.3), "baseline_nights": .int(4)], unit: "degC")
        let md = SummaryMarkdownSerializer().serialize(snap, flavor: .telegramV2)
        XCTAssertTrue(md.contains("4 of 5 nights"))
        XCTAssertFalse(md.contains("Change"))
    }
    func test_zonesAreIncludedInBothJSONExports() throws {
        var snap = snapshot()
        snap.workouts = [workout()]
        let summary = try XCTUnwrap(JSONSerialization.jsonObject(with: SummaryJSONSerializer().serialize(snap)) as? [String: Any])
        let workouts = try XCTUnwrap(summary["workouts"] as? [[String: Any]])
        let summaryZones = try XCTUnwrap(workouts.first?["heart_rate_zones"] as? [String: Any])
        XCTAssertEqual(summaryZones["lower_bounds_bpm"] as? [Int], [100, 120, 140, 160])
        XCTAssertEqual(summaryZones["seconds_by_zone"] as? [Double], [0, 30, 0, 0, 0])
        let file = try XCTUnwrap(WorkoutFilesSerializer().serialize(workouts: snap.workouts).first)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: file.data) as? [String: Any])
        let zones = try XCTUnwrap(json["heart_rate_zones"] as? [String: Any])
        XCTAssertEqual(zones["method"] as? String, "custom_thresholds_forward_hold_max_30s")
        XCTAssertEqual(zones["active_seconds"] as? Int, 60)
    }
    func test_legacyWorkoutWithoutZonesStillDecodes() throws {
        let w = workout()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(w)) as? [String: Any])
        json.removeValue(forKey: "heartRateZones")
        let decoded = try JSONDecoder().decode(WorkoutDTO.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.heartRateZones)
    }
    func test_malformedZoneArraysAreRejectedBeforeRendering() {
        let data = Data(#"{"lower_bounds_bpm":[100],"seconds_by_zone":[30],"active_seconds":60,"method":"custom"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(WorkoutHeartRateZones.self, from: data))
    }
}
