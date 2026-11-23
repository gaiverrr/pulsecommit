import Foundation

enum ExportWindowResolution: Sendable, Equatable {
    case proceed(from: Date, to: Date)
    /// The resolved window contains no completed days to export (e.g. a range
    /// that falls entirely inside today's still-incomplete day). Distinct from
    /// `proceed(from:to:)` with `from == to`, which downstream would deliver
    /// nothing yet record as a success.
    case empty(reason: String)
}

struct ExportWindowResolver: Sendable {
    var calendar: Calendar
    var timezone: TimeZone

    init(timezone: TimeZone = .current) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timezone
        self.calendar = cal
        self.timezone = timezone
    }

    func resolve(
        mode: ExportRequest.Mode,
        cursor: Date?,
        now: Date
    ) -> ExportWindowResolution {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today.addingTimeInterval(-86400)

        switch mode {
        case .lastDayOnly:
            return .proceed(from: yesterday, to: today)

        case .todayLive:
            return .proceed(from: today, to: now)

        case .incremental:
            var from = cursor.map { calendar.startOfDay(for: $0) } ?? yesterday
            if from > today { from = today }
            return .proceed(from: from, to: today)

        case .lastNDays(let n):
            let from = calendar.date(byAdding: .day, value: -n, to: today) ?? today.addingTimeInterval(-Double(n) * 86400)
            return .proceed(from: from, to: today)

        case .range(let from, let to):
            // Shortcuts date parameters carry a time of day; snap to whole days
            // so partial days are never committed as full ones. The range is
            // inclusive of the day that contains `to` (an instant at exactly
            // midnight belongs to that day, matching startOfDay semantics used
            // by every other mode — so the result is continuous across the
            // midnight boundary, with no one-day cliff). The end is clamped to
            // today's start because the current day is still incomplete.
            let snappedFrom = calendar.startOfDay(for: from)
            let dayAfterTo = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))
                ?? to
            let snappedTo = min(dayAfterTo, today)
            guard snappedFrom < snappedTo else {
                return .empty(reason: "the selected range has no completed days to export yet — today is still in progress")
            }
            return .proceed(from: snappedFrom, to: snappedTo)
        }
    }
}
