import Foundation

enum CategorySectionKind: String, CaseIterable, Identifiable {
    case activity
    case heart
    case sleepBodyMind
    case workouts
    case nutrition
    case lab

    var id: String { rawValue }

    var title: String {
        switch self {
        case .activity: return "ACTIVITY"
        case .heart: return "HEART"
        case .sleepBodyMind: return "SLEEP · BODY · MIND"
        case .workouts: return "WORKOUTS"
        case .nutrition: return "NUTRITION"
        case .lab: return "LAB · OPT-IN"
        }
    }
}

struct CategoryRowSpec: Identifiable, Hashable {
    enum Kind: Hashable {
        case registry(id: String)
        case bundledWith(id: String)
        case placeholder(id: String)
        case lab(LabFlag)
    }

    let kind: Kind
    let displayName: String
    let symbol: String

    var id: String {
        // Prefix with kind discriminator so two rows referencing the same
        // underlying category id stay unique inside ForEach. Without this,
        // both `.registry(id: "workouts")` and `.bundledWith(id: "workouts")`
        // resolved to "workouts" → SwiftUI ran into undefined-behavior diffing
        // and the Categories list froze the app.
        switch kind {
        case .registry(let id): return "registry:\(id)"
        case .bundledWith(let id): return "bundled:\(id)"
        case .placeholder(let id): return "placeholder:\(id)"
        case .lab(let flag): return "lab:\(flag.rawValue)"
        }
    }
}

enum CategoryCatalog {
    static let sections: [(CategorySectionKind, [CategoryRowSpec])] = [
        (.activity, [
            CategoryRowSpec(kind: .registry(id: "steps"), displayName: "Steps", symbol: "figure.walk"),
            CategoryRowSpec(kind: .registry(id: "distance_walking_running"), displayName: "Distance", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill"),
            CategoryRowSpec(kind: .registry(id: "active_energy"), displayName: "Active Energy", symbol: "flame.fill"),
            CategoryRowSpec(kind: .registry(id: "activity_rings"), displayName: "Activity Rings", symbol: "sparkles")
        ]),
        (.heart, [
            CategoryRowSpec(kind: .registry(id: "heart_rate"), displayName: "Heart Rate", symbol: "heart.fill"),
            CategoryRowSpec(kind: .registry(id: "resting_heart_rate"), displayName: "Resting HR", symbol: "heart.fill"),
            CategoryRowSpec(kind: .registry(id: "hrv_sdnn"), displayName: "HRV", symbol: "waveform.path.ecg"),
            CategoryRowSpec(kind: .registry(id: "vo2_max"), displayName: "VO₂ Max", symbol: "waveform.path.ecg")
        ]),
        (.sleepBodyMind, [
            CategoryRowSpec(kind: .registry(id: "sleep"), displayName: "Sleep", symbol: "moon.fill"),
            CategoryRowSpec(kind: .registry(id: "respiratory_rate"), displayName: "Sleep Respiratory Rate", symbol: "wind"),
            CategoryRowSpec(kind: .registry(id: "wrist_temperature"), displayName: "Wrist Temperature", symbol: "thermometer.medium"),
            CategoryRowSpec(kind: .registry(id: "body_mass"), displayName: "Body Mass", symbol: "scalemass.fill"),
            CategoryRowSpec(kind: .registry(id: "state_of_mind"), displayName: "State of Mind", symbol: "brain")
        ]),
        (.workouts, [
            CategoryRowSpec(kind: .registry(id: "workouts"), displayName: "Workouts", symbol: "flame.fill"),
            CategoryRowSpec(kind: .bundledWith(id: "workouts"), displayName: "Workout Routes", symbol: "point.topleft.down.to.point.bottomright.curvepath.fill")
        ]),
        (.nutrition, [
            CategoryRowSpec(kind: .registry(id: "nutrition"), displayName: "Food & Macros", symbol: "fork.knife"),
            CategoryRowSpec(kind: .placeholder(id: "hydration"), displayName: "Water · Caffeine", symbol: "waveform.path.ecg")
        ]),
        (.lab, [
            CategoryRowSpec(kind: .lab(.bloodOxygen), displayName: LabFlag.bloodOxygen.displayName, symbol: LabFlag.bloodOxygen.symbol),
            CategoryRowSpec(kind: .lab(.mindfulMinutes), displayName: LabFlag.mindfulMinutes.displayName, symbol: LabFlag.mindfulMinutes.symbol)
        ])
    ]

    static func enabledCount(in section: CategorySectionKind, enabledIds: Set<String>) -> Int {
        let rows = sections.first(where: { $0.0 == section })?.1 ?? []
        return rows.reduce(0) { acc, spec in
            switch spec.kind {
            case .registry(let id): return acc + (enabledIds.contains(id) ? 1 : 0)
            case .bundledWith(let id): return acc + (enabledIds.contains(id) ? 1 : 0)
            case .placeholder, .lab: return acc
            }
        }
    }

    static func totalCount(in section: CategorySectionKind) -> Int {
        sections.first(where: { $0.0 == section })?.1.count ?? 0
    }
}
