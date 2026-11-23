import Foundation

public enum DateBucketing {
    public static func dayKey(_ date: Date, in timezone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public static func startOfDay(_ date: Date, in timezone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        return calendar.startOfDay(for: date)
    }

    public static func daysCovered(from: Date, to: Date, in timezone: TimeZone) -> [String] {
        days(from: from, to: to, in: timezone).map { $0.key }
    }

    public static func days(from: Date, to: Date, in timezone: TimeZone) -> [(key: String, dayStart: Date)] {
        guard from < to else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone

        var current = calendar.startOfDay(for: from)
        var out: [(key: String, dayStart: Date)] = []
        while current < to {
            out.append((dayKey(current, in: timezone), current))
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return out
    }
}
