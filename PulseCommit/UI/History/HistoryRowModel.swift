import Foundation

struct HistoryRowModel: Identifiable, Hashable {
    enum Outcome: Hashable {
        case success
        case failed
    }

    struct SinkBadge: Hashable {
        var label: String
        var ok: Bool
        var kind: String? = nil
    }

    var id: UUID
    var outcome: Outcome
    var shortHash: String?
    var dateLabel: String
    var relativeTime: String
    var summary: String
    var sinkBadges: [SinkBadge]

    static func from(
        snapshot: HistoryEntrySnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HistoryRowModel {
        let isSuccess = snapshot.status == .success
        let summary: String
        if isSuccess {
            let days = snapshot.daysCovered.count
            summary = days == 1
                ? "exported 1 day"
                : "exported \(days) days"
        } else {
            summary = snapshot.displayErrorMessage ?? "export failed"
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateLabel = dateFormatter.string(from: snapshot.startedAt)

        let relative = HistoryRowModel.relativeTimeLabel(
            for: snapshot.startedAt,
            now: now,
            calendar: calendar,
            locale: locale
        )

        let badges: [SinkBadge] = snapshot.sinks.map { name in
            if name == WebhookDestinationSink.sinkID, isSuccess, let reference = snapshot.webhookReference {
                return SinkBadge(label: reference, ok: true, kind: name)
            }
            return SinkBadge(label: name, ok: isSuccess, kind: name)
        }

        let shortHash = snapshot.githubCommitSha.map { String($0.prefix(8)) }

        return HistoryRowModel(
            id: snapshot.id,
            outcome: isSuccess ? .success : .failed,
            shortHash: shortHash,
            dateLabel: dateLabel,
            relativeTime: relative,
            summary: summary,
            sinkBadges: badges
        )
    }

    /// Convenience overload used by tests that already hold a live `HistoryEntry`.
    /// UI code paths must always use the snapshot variant — `@Model` instances
    /// must not cross context boundaries.
    static func from(
        entry: HistoryEntry,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> HistoryRowModel {
        from(snapshot: HistoryEntrySnapshot(entry: entry), now: now, calendar: calendar, locale: locale)
    }

    private static func relativeTimeLabel(
        for date: Date,
        now: Date,
        calendar: Calendar,
        locale: Locale
    ) -> String {
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0

        let prefix: String
        switch dayDelta {
        case 0: prefix = "Today"
        case 1: prefix = "Yesterday"
        default:
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = calendar.timeZone
            df.dateFormat = "MMM d"
            prefix = df.string(from: date)
        }
        return "\(prefix) · \(time)"
    }
}
