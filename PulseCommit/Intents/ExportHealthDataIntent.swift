import AppIntents
import Foundation

struct ExportHealthDataIntent: AppIntent {
    static let title: LocalizedStringResource = "Export Health Data"
    static let description = IntentDescription(
        "Exports a window of health data to one or both destinations."
    )

    static let openAppWhenRun: Bool = false

    @Parameter(title: "Window", default: .last1d)
    var window: WindowOption

    @Parameter(title: "Destinations", default: .both)
    var destinations: DestinationOption

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let status = try await IntentRunner.run(
            mode: IntentRunner.exportMode(for: window),
            sinkFilter: destinations.sinkIds
        )
        return .result(value: status)
    }
}
