import Foundation

enum LabFlag: String, CaseIterable, Identifiable {
    case bloodOxygen = "blood_oxygen"
    case mindfulMinutes = "mindful_minutes"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bloodOxygen: return "Blood Oxygen"
        case .mindfulMinutes: return "Mindful Minutes"
        }
    }

    var symbol: String {
        switch self {
        case .bloodOxygen: return "drop.fill"
        case .mindfulMinutes: return "figure.mind.and.body"
        }
    }
}
