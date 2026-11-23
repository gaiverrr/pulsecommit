import XCTest
import HealthKit
import HealthCore
@testable import PulseCommit

final class SleepCategoryTests: XCTestCase {
    private let store = NullStore()

    private func sample(
        value: Int,
        durationMinutes: Double,
        at start: Date,
        source: String = "Test"
    ) -> CategorySampleDTO {
        CategorySampleDTO(
            categoryID: "sleep",
            startDate: start,
            endDate: start.addingTimeInterval(durationMinutes * 60),
            value: value,
            metadata: [:],
            sourceName: source,
            sourceBundleID: "test.bundle.\(source)"
        )
    }

    func test_id_isStable() {
        XCTAssertEqual(SleepCategory(store: store).id, "sleep")
    }

    func test_summarize_aggregatesStages() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, durationMinutes: 60, at: base),
            sample(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, durationMinutes: 30, at: base.addingTimeInterval(3600)),
            sample(value: HKCategoryValueSleepAnalysis.asleepREM.rawValue, durationMinutes: 90, at: base.addingTimeInterval(7200)),
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 180, at: base.addingTimeInterval(14400)),
            sample(value: HKCategoryValueSleepAnalysis.awake.rawValue, durationMinutes: 15, at: base.addingTimeInterval(28800)),
            sample(value: HKCategoryValueSleepAnalysis.inBed.rawValue, durationMinutes: 480, at: base)
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_deep"], .int(90))
        XCTAssertEqual(frag.metrics["stage_rem"], .int(90))
        XCTAssertEqual(frag.metrics["stage_core"], .int(180))
        XCTAssertEqual(frag.metrics["stage_awake"], .int(15))
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(360))
        XCTAssertEqual(frag.unit, "min")
    }

    func test_summarize_emptyProducesZeroMetrics() {
        let cat = SleepCategory(store: store)
        let frag = cat.summarize([])
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(0))
        XCTAssertEqual(frag.metrics["stage_deep"], .int(0))
        XCTAssertEqual(frag.metrics["stage_rem"], .int(0))
        XCTAssertEqual(frag.metrics["stage_core"], .int(0))
        XCTAssertEqual(frag.metrics["stage_awake"], .int(0))
    }

    func test_summarize_identicalIntervalsFromTwoSourcesCountOnce() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 480, at: base, source: "Watch"),
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 480, at: base, source: "AutoSleep")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_core"], .int(480))
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(480))
    }

    func test_summarize_partiallyOverlappingIntervalsCountUnion() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 120, at: base, source: "Watch"),
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 120, at: base.addingTimeInterval(3600), source: "AutoSleep")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_core"], .int(180))
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(180))
    }

    func test_summarize_overlappingPerStageMinutesMergeWithinEachStage() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, durationMinutes: 60, at: base, source: "Watch"),
            sample(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, durationMinutes: 60, at: base.addingTimeInterval(1800), source: "AutoSleep"),
            sample(value: HKCategoryValueSleepAnalysis.awake.rawValue, durationMinutes: 20, at: base.addingTimeInterval(7200), source: "Watch"),
            sample(value: HKCategoryValueSleepAnalysis.awake.rawValue, durationMinutes: 20, at: base.addingTimeInterval(7200), source: "AutoSleep")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_deep"], .int(90))
        XCTAssertEqual(frag.metrics["stage_awake"], .int(20))
    }

    func test_summarize_crossStageOverlapDoesNotInflateTotalDuration() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepDeep.rawValue, durationMinutes: 480, at: base, source: "Watch"),
            sample(value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, durationMinutes: 480, at: base, source: "AutoSleep")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_deep"], .int(480))
        XCTAssertEqual(frag.metrics["stage_core"], .int(480))
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(480))
    }

    func test_summarize_disjointSamplesFromTwoSourcesStillSum() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 60, at: base, source: "Watch"),
            sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, durationMinutes: 60, at: base.addingTimeInterval(7200), source: "AutoSleep")
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_core"], .int(120))
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(120))
    }

    func test_summarize_asleepUnspecifiedFoldsIntoCore() {
        let cat = SleepCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let s: [any SampleDTO] = [
            sample(value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, durationMinutes: 45, at: base)
        ]
        let frag = cat.summarize(s)
        XCTAssertEqual(frag.metrics["stage_core"], .int(45))
        XCTAssertEqual(frag.metrics["duration_minutes"], .int(45))
    }
}
