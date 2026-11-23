import AppIntents
import Foundation

struct BackfillRangeIntent: AppIntent {
    static let title: LocalizedStringResource = "Backfill Range"
    static let description = IntentDescription(
        "Exports a custom date range of up to 365 days."
    )

    static let openAppWhenRun: Bool = false

    @Parameter(title: "From")
    var from: Date

    @Parameter(title: "To")
    var to: Date

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let clampedTo = min(to, Date())
        guard from < clampedTo else {
            throw IntentError.invalidRange
        }
        // Cap the span in whole calendar days, inclusive of both endpoint days,
        // to match what ExportWindowResolver.range actually exports — measuring
        // the raw TimeInterval let a 365-day request whose `to` lands at
        // midnight export 366 days once the resolver snaps the end forward.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let fromDay = cal.startOfDay(for: from)
        let toDay = cal.startOfDay(for: clampedTo)
        let inclusiveDayCount = (cal.dateComponents([.day], from: fromDay, to: toDay).day ?? 0) + 1
        guard inclusiveDayCount <= 365 else {
            throw IntentError.invalidRange
        }
        let status = try await IntentRunner.run(mode: .range(from: from, to: clampedTo))
        return .result(value: status)
    }
}

struct PulseCommitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ExportLastDayIntent(),
            phrases: [
                "Export last day with \(.applicationName)",
                "\(.applicationName) export yesterday"
            ],
            shortTitle: "Export Last Day",
            systemImageName: "arrow.up.doc"
        )
        AppShortcut(
            intent: ExportHealthDataIntent(),
            phrases: [
                "Export health data with \(.applicationName)",
                "\(.applicationName) export window"
            ],
            shortTitle: "Export Health Data",
            systemImageName: "square.and.arrow.up"
        )
        AppShortcut(
            intent: BackfillRangeIntent(),
            phrases: [
                "Backfill range with \(.applicationName)",
                "\(.applicationName) backfill"
            ],
            shortTitle: "Backfill Range",
            systemImageName: "calendar.badge.clock"
        )
    }
}
