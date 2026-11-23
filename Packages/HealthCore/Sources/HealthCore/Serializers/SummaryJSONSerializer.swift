import Foundation

public struct SummaryJSONSerializer: Sendable {
    public init() {}

    public func serialize(_ snapshot: DailySnapshot) throws -> Data {
        let payload = SummaryPayload(snapshot: snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(SummaryJSONSerializer.iso8601.string(from: date))
        }
        return try encoder.encode(payload)
    }

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func dayKey(for date: Date, timezone: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: timezone) ?? .gmt
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

private struct SummaryPayload: Encodable {
    let snapshot: DailySnapshot

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case date
        case timezone
        case generatedAt = "generated_at"
        case latestSampleAt = "latest_sample_at"
        case device
        case appVersion = "app_version"
        case unavailableCategories = "unavailable_categories"
        case metrics
        case workouts
        case stateOfMind = "state_of_mind"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(snapshot.schemaVersion, forKey: .schemaVersion)
        try c.encode(SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone), forKey: .date)
        try c.encode(snapshot.timezone, forKey: .timezone)
        try c.encode(snapshot.generatedAt, forKey: .generatedAt)
        try c.encodeIfPresent(snapshot.latestSampleAt, forKey: .latestSampleAt)
        try c.encode(snapshot.deviceName, forKey: .device)
        try c.encode(snapshot.appVersion, forKey: .appVersion)
        try c.encode(snapshot.unavailableCategories, forKey: .unavailableCategories)

        var metricsContainer = c.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .metrics)
        for (categoryID, fragment) in snapshot.summaries {
            let key = DynamicCodingKey(stringValue: categoryID)!
            try metricsContainer.encode(CategoryMetricsPayload(fragment: fragment), forKey: key)
        }

        try c.encode(snapshot.workouts.map(WorkoutPayload.init), forKey: .workouts)
        try c.encode(snapshot.stateOfMind.map(StateOfMindPayload.init), forKey: .stateOfMind)
    }
}

private struct CategoryMetricsPayload: Encodable {
    let fragment: SummaryFragment

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: DynamicCodingKey.self)
        for (k, v) in fragment.metrics {
            try c.encode(v, forKey: DynamicCodingKey(stringValue: k)!)
        }
        if let unit = fragment.unit {
            try c.encode(unit, forKey: DynamicCodingKey(stringValue: "unit")!)
        }
    }
}

private struct WorkoutPayload: Encodable {
    let workout: WorkoutDTO

    init(_ workout: WorkoutDTO) { self.workout = workout }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case startDate = "start_date"
        case endDate = "end_date"
        case durationMinutes = "duration_minutes"
        case durationSeconds = "duration_seconds"
        case distanceKm = "distance_km"
        case distanceMeters = "distance_meters"
        case averagePaceSecondsPerKilometer = "average_pace_seconds_per_km"
        case averageSpeedKilometersPerHour = "average_speed_kph"
        case activeEnergyKcal = "active_energy_kcal"
        case avgHr = "avg_hr"
        case maxHr = "max_hr"
        case heartRateZones = "heart_rate_zones"
        case recordedIntervals = "recorded_intervals"
        case hasRoute = "has_route"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(workout.id, forKey: .id)
        try c.encode(workout.type.rawValue, forKey: .type)
        try c.encode(workout.startDate, forKey: .startDate)
        try c.encode(workout.endDate, forKey: .endDate)
        try c.encode(workout.durationMinutes, forKey: .durationMinutes)
        try c.encodeIfPresent(workout.durationSeconds, forKey: .durationSeconds)
        try c.encodeIfPresent(workout.distanceKm, forKey: .distanceKm)
        try c.encodeIfPresent(workout.distanceMeters, forKey: .distanceMeters)
        try c.encodeIfPresent(workout.averagePaceSecondsPerKilometer.map(roundToSixPlaces), forKey: .averagePaceSecondsPerKilometer)
        try c.encodeIfPresent(workout.averageSpeedKilometersPerHour.map(roundToSixPlaces), forKey: .averageSpeedKilometersPerHour)
        try c.encodeIfPresent(workout.activeEnergyKcal, forKey: .activeEnergyKcal)
        try c.encodeIfPresent(workout.avgHeartRate, forKey: .avgHr)
        try c.encodeIfPresent(workout.maxHeartRate, forKey: .maxHr)
        try c.encodeIfPresent(workout.heartRateZones, forKey: .heartRateZones)
        try c.encodeIfPresent(workout.recordedIntervals, forKey: .recordedIntervals)
        try c.encode(workout.hasRoute, forKey: .hasRoute)
    }

    private func roundToSixPlaces(_ value: Double) -> Double {
        guard abs(value) <= Double.greatestFiniteMagnitude / 1_000_000 else { return value }
        return (value * 1_000_000).rounded() / 1_000_000
    }
}

private struct StateOfMindPayload: Encodable {
    let entry: StateOfMindEntryDTO

    init(_ entry: StateOfMindEntryDTO) { self.entry = entry }

    enum CodingKeys: String, CodingKey {
        case time, valence, labels
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entry.time, forKey: .time)
        try c.encode(entry.valence, forKey: .valence)
        try c.encode(entry.labels, forKey: .labels)
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
