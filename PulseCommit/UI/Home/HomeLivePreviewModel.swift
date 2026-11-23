import Foundation
import Observation
import HealthCore

@MainActor
@Observable
final class HomeLivePreviewModel {
    enum Window: Equatable {
        case today
        case yesterday
    }

    var todaySteps: Int?
    var todayActiveKcal: Double?
    var todaySleepMinutes: Int?
    var todayWorkoutCount: Int?

    var yesterdaySteps: Int?
    var yesterdayActiveKcal: Double?
    var yesterdaySleepMinutes: Int?
    var yesterdayWorkoutCount: Int?

    var currentMode: Window = .today

    private let registry: CategoryRegistry
    private let now: @MainActor () -> Date
    private let calendar: Calendar

    init(
        registry: CategoryRegistry,
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.registry = registry
        self.calendar = calendar
        self.now = now
    }

    func refresh(mode: Window? = nil) async {
        if let mode { currentMode = mode }
        switch currentMode {
        case .today:
            await refreshTodayWindow()
        case .yesterday:
            await refreshYesterdayWindow()
        }
    }

    private func refreshTodayWindow() async {
        let to = now()
        let from = calendar.startOfDay(for: to)
        let result = await fetchAll(from: from, to: to)
        todaySteps = result.steps
        todayActiveKcal = result.kcal
        todaySleepMinutes = result.sleepMinutes
        todayWorkoutCount = result.workouts
    }

    private func refreshYesterdayWindow() async {
        let todayStart = calendar.startOfDay(for: now())
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart.addingTimeInterval(-86400)
        let result = await fetchAll(from: yesterdayStart, to: todayStart)
        yesterdaySteps = result.steps
        yesterdayActiveKcal = result.kcal
        yesterdaySleepMinutes = result.sleepMinutes
        yesterdayWorkoutCount = result.workouts
    }

    var displaySteps: Int? {
        currentMode == .today ? todaySteps : yesterdaySteps
    }

    var displayActiveKcal: Double? {
        currentMode == .today ? todayActiveKcal : yesterdayActiveKcal
    }

    var displaySleepMinutes: Int? {
        currentMode == .today ? todaySleepMinutes : yesterdaySleepMinutes
    }

    var displayWorkoutCount: Int? {
        currentMode == .today ? todayWorkoutCount : yesterdayWorkoutCount
    }

    private struct WindowResult {
        var steps: Int?
        var kcal: Double?
        var sleepMinutes: Int?
        var workouts: Int?
    }

    private func fetchAll(from: Date, to: Date) async -> WindowResult {
        var result = WindowResult()
        result.steps = await fetchInt(categoryID: "steps", metric: "total", from: from, to: to)
        result.kcal = await fetchDouble(categoryID: "active_energy", metric: "total", from: from, to: to)
        result.sleepMinutes = await fetchInt(categoryID: "sleep", metric: "duration_minutes", from: from, to: to)
        result.workouts = await fetchInt(categoryID: "workouts", metric: "count", from: from, to: to)
        return result
    }

    private func fetchInt(categoryID: String, metric: String, from: Date, to: Date) async -> Int? {
        guard let category = registry.category(withId: categoryID) else { return nil }
        do {
            let samples = try await category.fetchSummarySamples(from: from, to: to)
            guard !samples.isEmpty else { return nil }
            let fragment = category.summarize(samples)
            if case .int(let value) = fragment.metrics[metric] {
                return value
            }
            return nil
        } catch {
            return nil
        }
    }

    private func fetchDouble(categoryID: String, metric: String, from: Date, to: Date) async -> Double? {
        guard let category = registry.category(withId: categoryID) else { return nil }
        do {
            let samples = try await category.fetchSummarySamples(from: from, to: to)
            guard !samples.isEmpty else { return nil }
            let fragment = category.summarize(samples)
            if case .int(let value) = fragment.metrics[metric] {
                return Double(value)
            } else if case .double(let value) = fragment.metrics[metric] {
                return value
            }
            return nil
        } catch {
            return nil
        }
    }

    static func formatSteps(_ value: Int?) -> String {
        guard let value else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func formatKcal(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))"
    }

    static func formatSleep(_ minutes: Int?) -> String {
        guard let minutes else { return "—" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    static func formatWorkouts(_ value: Int?) -> String {
        guard let value else { return "—" }
        return "\(value)"
    }
}
