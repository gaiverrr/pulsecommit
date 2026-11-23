import XCTest
@testable import PulseCommit

@MainActor
final class HomePeriodPillTests: XCTestCase {
    func test_currentPeriod_defaultsToToday() {
        let viewModel = HomeViewModel(
            runRequest: { _, _ in .success },
            enabledCategoryIds: { [] },
            enabledSinkIds: { [] }
        )
        XCTAssertEqual(viewModel.currentPeriod, .today)
    }

    func test_runExport_withYesterdayOverride_dispatchesLastDayOnly() async {
        var captured: ExportRequest?
        let viewModel = HomeViewModel(
            runRequest: { req, _ in
                captured = req
                return .success
            },
            enabledCategoryIds: { [] },
            enabledSinkIds: { ["github"] }
        )
        await viewModel.runExport(sinkOverride: nil, modeOverride: .lastDayOnly)
        XCTAssertEqual(captured?.mode, .lastDayOnly)
    }

    func test_runExport_withTodayOverride_dispatchesTodayLive() async {
        var captured: ExportRequest?
        let viewModel = HomeViewModel(
            runRequest: { req, _ in
                captured = req
                return .success
            },
            enabledCategoryIds: { [] },
            enabledSinkIds: { ["github"] }
        )
        await viewModel.runExport(sinkOverride: nil, modeOverride: .todayLive)
        XCTAssertEqual(captured?.mode, .todayLive)
    }
}
