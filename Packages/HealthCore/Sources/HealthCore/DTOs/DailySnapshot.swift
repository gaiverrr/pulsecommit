import Foundation

public struct StateOfMindEntryDTO: Codable, Equatable, Hashable, Sendable {
    public let time: Date
    public let valence: Double
    public let labels: [String]

    public init(time: Date, valence: Double, labels: [String]) {
        self.time = time
        self.valence = valence
        self.labels = labels
    }
}

public struct DailySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let date: Date
    public let timezone: String
    public let generatedAt: Date
    public let deviceName: String
    public let appVersion: String

    public var unavailableCategories: [String]
    public var summaries: [String: SummaryFragment]
    public var workouts: [WorkoutDTO]
    public var stateOfMind: [StateOfMindEntryDTO]
    public var latestSampleAt: Date?

    public init(
        date: Date,
        timezone: String,
        generatedAt: Date,
        deviceName: String,
        appVersion: String
    ) {
        self.schemaVersion = SchemaVersion.current
        self.date = date
        self.timezone = timezone
        self.generatedAt = generatedAt
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.unavailableCategories = []
        self.summaries = [:]
        self.workouts = []
        self.stateOfMind = []
        self.latestSampleAt = nil
    }
}
