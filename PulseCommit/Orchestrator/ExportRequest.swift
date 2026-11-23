import Foundation

struct ExportRequest: Sendable, Equatable {
    enum Mode: Sendable, Equatable {
        case incremental
        case lastNDays(Int)
        case range(from: Date, to: Date)
        case lastDayOnly
        case todayLive
    }

    var mode: Mode
    var enabledCategoryIds: Set<String>
    var enabledSinkIds: Set<String>

    init(
        mode: Mode,
        enabledCategoryIds: Set<String>,
        enabledSinkIds: Set<String>
    ) {
        self.mode = mode
        self.enabledCategoryIds = enabledCategoryIds
        self.enabledSinkIds = enabledSinkIds
    }
}
