import Foundation

/// Builds the single text-only Telegram message used by automatic workout delivery.
/// It intentionally has no access to route points, raw samples, daily summaries, or
/// custom heart-rate zones.
public struct AutomaticWorkoutMessageRenderer: Sendable {
    public static let telegramTextLimit = 4_096

    public init() {}

    public func render(workout: WorkoutDTO, timeZoneIdentifier: String) -> String {
        var lines = ["🏁 *Workout finished*"]
        let details = WorkoutDetailFormatter(
            timeZoneIdentifier: timeZoneIdentifier,
            includesDate: true,
            includesHeartRateZones: false,
            remainderStyle: .omitted
        ).lines(for: workout)
        lines.append(contentsOf: details.map(MarkdownV2Escaper.escape))

        // All producer-controlled fields are bounded, but retain a defensive
        // one-message guarantee if future DTO fields become free-form.
        while lines.joined(separator: "\n").utf8.count > Self.telegramTextLimit, lines.count > 4 {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

}
