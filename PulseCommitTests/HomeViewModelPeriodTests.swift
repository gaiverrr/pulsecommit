import HealthCore
import XCTest
@testable import PulseCommit

@MainActor
final class HomeViewModelPeriodTests: XCTestCase {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return cal
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 5
        comps.day = 15
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps)!
    }

    private func makeModel(
        clock: @escaping @MainActor () -> Date = { Date() },
        initialPeriod: HomeViewModel.Period = .today,
        run: @escaping @MainActor (ExportRequest, RunProgressHandler?) async -> Orchestrator.RunResult = { _, _ in .success }
    ) -> HomeViewModel {
        HomeViewModel(
            runRequest: run,
            enabledCategoryIds: { [] },
            enabledSinkIds: { ["github"] },
            clock: clock,
            calendar: calendar,
            initialPeriod: initialPeriod
        )
    }

    func test_period_storageRoundTrip() {
        XCTAssertEqual(HomeViewModel.Period(storageKey: "today"), .today)
        XCTAssertEqual(HomeViewModel.Period(storageKey: "yesterday"), .yesterday)
        XCTAssertEqual(HomeViewModel.Period(storageKey: "last_7_days"), .last7Days)
        XCTAssertEqual(HomeViewModel.Period(storageKey: "last_30_days"), .last30Days)
        // No UI path can select .custom until a real date-picker ships;
        // a stale persisted "custom" must restore to an honest, pickable value.
        XCTAssertEqual(HomeViewModel.Period(storageKey: "custom"), .today)
        XCTAssertEqual(HomeViewModel.Period(storageKey: "garbage"), .today)
        XCTAssertEqual(HomeViewModel.Period.yesterday.storageKey, "yesterday")
        XCTAssertEqual(HomeViewModel.Period.last7Days.storageKey, "last_7_days")
    }

    func test_initialPeriod_today_isRespectedRegardlessOfHour() {
        let amModel = makeModel(clock: { self.date(hour: 4) }, initialPeriod: .today)
        XCTAssertEqual(amModel.currentPeriod, .today)
    }

    func test_initialPeriod_yesterday_isRespectedRegardlessOfHour() {
        let pmModel = makeModel(clock: { self.date(hour: 22) }, initialPeriod: .yesterday)
        XCTAssertEqual(pmModel.currentPeriod, .yesterday)
    }

    func test_runExport_usesCurrentPeriod_today() async {
        var captured: ExportRequest?
        let model = makeModel(
            clock: { self.date(hour: 6) },
            initialPeriod: .today,
            run: { request, _ in
                captured = request
                return .success
            }
        )
        await model.runExport()
        XCTAssertEqual(captured?.mode, .todayLive)
    }

    func test_runExport_usesCurrentPeriod_yesterday() async {
        var captured: ExportRequest?
        let model = makeModel(
            clock: { self.date(hour: 18) },
            initialPeriod: .yesterday,
            run: { request, _ in
                captured = request
                return .success
            }
        )
        await model.runExport()
        XCTAssertEqual(captured?.mode, .lastDayOnly)
    }

    func test_runExport_usesCurrentPeriod_last7Days() async {
        var captured: ExportRequest?
        let model = makeModel(
            initialPeriod: .last7Days,
            run: { request, _ in
                captured = request
                return .success
            }
        )
        await model.runExport()
        XCTAssertEqual(captured?.mode, .lastNDays(7))
    }

    func test_runExport_modeOverrideTakesPrecedence() async {
        var captured: ExportRequest?
        let model = makeModel(
            initialPeriod: .today,
            run: { request, _ in
                captured = request
                return .success
            }
        )
        await model.runExport(modeOverride: .lastNDays(30))
        XCTAssertEqual(captured?.mode, .lastNDays(30))
    }

    func test_changingCurrentPeriod_dispatchesNewMode() async {
        var captured: ExportRequest?
        let model = makeModel(
            initialPeriod: .today,
            run: { request, _ in
                captured = request
                return .success
            }
        )
        model.currentPeriod = .last30Days
        await model.runExport()
        XCTAssertEqual(captured?.mode, .lastNDays(30))
    }

    func test_periodPersistsRoundTrip_viaPreferencesStore() {
        let suite = "test.periods.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = PreferencesStore(defaults: defaults)
        XCTAssertEqual(prefs.selectedPeriod, "today")
        prefs.selectedPeriod = "yesterday"
        let reloaded = PreferencesStore(defaults: defaults)
        XCTAssertEqual(reloaded.selectedPeriod, "yesterday")
        XCTAssertEqual(HomeViewModel.Period(storageKey: reloaded.selectedPeriod), .yesterday)
    }
}
