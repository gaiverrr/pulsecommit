import Foundation

public struct WorkoutFilesSerializer: Sendable {
    private let gpx: GPXEncoder

    public init(gpx: GPXEncoder = GPXEncoder()) {
        self.gpx = gpx
    }

    public func serialize(workouts: [WorkoutDTO]) throws -> [FileEntry] {
        var files: [FileEntry] = []
        for workout in workouts {
            let slug = "\(workout.id)-\(Self.typeSlug(workout.type))"
            let jsonData = try Self.encodeWorkoutJSON(workout)
            files.append(FileEntry(path: "workouts/\(slug).json", data: jsonData))
            if workout.hasRoute {
                let gpxData = gpx.encode(name: slug, points: workout.route)
                files.append(FileEntry(path: "routes/\(slug).gpx", data: gpxData))
            }
        }
        return files
    }

    static func typeSlug(_ type: WorkoutDTO.WorkoutType) -> String {
        type.rawValue.replacingOccurrences(of: "_", with: "-")
    }

    static func encodeWorkoutJSON(_ workout: WorkoutDTO) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(GPXEncoder.iso8601.string(from: date))
        }
        return try encoder.encode(WorkoutFilePayload(workout: workout))
    }
}

private struct WorkoutFilePayload: Encodable {
    let workout: WorkoutDTO

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
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
        try c.encode(SchemaVersion.current, forKey: .schemaVersion)
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
