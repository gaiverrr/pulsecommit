import XCTest
import HealthCore
@testable import PulseCommit

@MainActor
final class HomeViewLayoutTests: XCTestCase {
    func test_livePreviewExposesBothTodayAndYesterdayQuartet() async {
        let registry = CategoryRegistry(categories: [])
        let model = HomeLivePreviewModel(registry: registry)
        // Initial state — both windows are nil and currentMode defaults to .today.
        XCTAssertNil(model.todaySteps)
        XCTAssertNil(model.yesterdaySteps)
        XCTAssertNil(model.todayWorkoutCount)
        XCTAssertNil(model.yesterdayWorkoutCount)
        XCTAssertNil(model.todaySleepMinutes)
        XCTAssertNil(model.yesterdaySleepMinutes)
        XCTAssertNil(model.todayActiveKcal)
        XCTAssertNil(model.yesterdayActiveKcal)
        XCTAssertEqual(model.currentMode, .today)
    }

    func test_statTileHeroHeight_isLockedAtDesignTokenBaseline() {
        // The hero number box must be tall enough to accommodate the unscaled
        // `pcHeroNumber` glyph height; otherwise a scaled-down value (e.g.
        // "46 592" via .minimumScaleFactor) collapses its tile vertically and
        // the 2x2 grid renders uneven (the original Steps/Sleep vs Workouts/
        // KCAL bug). 64pt monospaced bold's natural line box is ~76pt.
        XCTAssertEqual(HomeView.statTileHeroHeight, 76)
    }

    func test_bigButtonMinHeight_isLockedToPreventLayoutShiftAcrossPhases() {
        // The big Export button's inner content varies per phase: running
        // adds a 3pt progress bar, done/error swap the sub-label. Without a
        // fixed minimum height, the LAST COMMIT card below moves a few
        // points on every phase change. Lock to at least 180pt so all four
        // phases share the same vertical footprint.
        XCTAssertGreaterThanOrEqual(HomeView.bigButtonMinHeight, 180)
    }

    func test_currentModeUpdatesOnRefresh() async {
        let registry = CategoryRegistry(categories: [])
        let model = HomeLivePreviewModel(registry: registry)
        await model.refresh(mode: .yesterday)
        XCTAssertEqual(model.currentMode, .yesterday)
        await model.refresh(mode: .today)
        XCTAssertEqual(model.currentMode, .today)
    }
}
