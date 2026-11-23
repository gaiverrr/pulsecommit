import AppIntents

struct ExportLastDayIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Last Day"
    static let description = IntentDescription(
        "Exports yesterday's health data to your configured destinations."
    )

    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let status = try await IntentRunner.run(mode: .lastDayOnly)
        return .result(value: status)
    }
}
