import Foundation
import SwiftData

@Model
final class ExportCursor {
    @Attribute(.unique) var key: String
    var lastSuccessfulExportAt: Date?

    init(key: String = "main", lastSuccessfulExportAt: Date? = nil) {
        self.key = key
        self.lastSuccessfulExportAt = lastSuccessfulExportAt
    }
}
