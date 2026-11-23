import Foundation

public struct RoutePointDTO: Codable, Equatable, Hashable, Sendable {
    public let time: Date
    public let latitude: Double
    public let longitude: Double
    public let elevationMeters: Double?

    public init(time: Date, latitude: Double, longitude: Double, elevationMeters: Double?) {
        self.time = time
        self.latitude = latitude
        self.longitude = longitude
        self.elevationMeters = elevationMeters
    }

    private enum CodingKeys: String, CodingKey {
        case time
        case latitude = "lat"
        case longitude = "lon"
        case elevationMeters
    }
}

public struct WorkoutRecordedIntervalDTO: Codable, Equatable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case lap
        case segment
    }

    public let kind: Kind
    public let startDate: Date
    public let endDate: Date
    public let durationSeconds: Double

    public init(kind: Kind, startDate: Date, endDate: Date, durationSeconds: Double) {
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case startDate = "start_date"
        case endDate = "end_date"
        case durationSeconds = "duration_seconds"
    }
}

public struct WorkoutDTO: Codable, Equatable, Hashable, Sendable {
    public enum WorkoutType: String, Codable, Sendable {
        case outdoorRun = "outdoor_run"
        case indoorRun = "indoor_run"
        case outdoorCycling = "outdoor_cycling"
        case indoorCycling = "indoor_cycling"
        case functionalStrengthTraining = "functional_strength_training"
        case traditionalStrengthTraining = "traditional_strength_training"
        case walking = "walking"
        case hiking = "hiking"
        case yoga = "yoga"
        case swimming = "swimming"
        case other = "other"
    }

    public let id: String
    public let type: WorkoutType
    public let startDate: Date
    public let endDate: Date
    public let durationMinutes: Int
    public let distanceKm: Double?
    public let activeEnergyKcal: Double?
    public let avgHeartRate: Double?
    public let maxHeartRate: Double?
    public let route: [RoutePointDTO]
    public let heartRateZones: WorkoutHeartRateZones?
    public let durationSeconds: Double?
    public let distanceMeters: Double?
    public let recordedIntervals: [WorkoutRecordedIntervalDTO]?

    public var hasRoute: Bool { !route.isEmpty }

    public var averagePaceSecondsPerKilometer: Double? {
        guard [.outdoorRun, .indoorRun, .walking, .hiking].contains(type),
              let durationSeconds,
              let distanceMeters,
              durationSeconds.isFinite,
              distanceMeters.isFinite,
              durationSeconds > 0,
              distanceMeters > 0 else {
            return nil
        }
        let value = durationSeconds / (distanceMeters / 1_000)
        return value.isFinite && value > 0 ? value : nil
    }

    public var averageSpeedKilometersPerHour: Double? {
        guard [.outdoorCycling, .indoorCycling].contains(type),
              let durationSeconds,
              let distanceMeters,
              durationSeconds.isFinite,
              distanceMeters.isFinite,
              durationSeconds > 0,
              distanceMeters > 0 else {
            return nil
        }
        let value = (distanceMeters / 1_000) / (durationSeconds / 3_600)
        return value.isFinite && value > 0 ? value : nil
    }

    public init(
        id: String,
        type: WorkoutType,
        startDate: Date,
        endDate: Date,
        durationMinutes: Int,
        distanceKm: Double?,
        activeEnergyKcal: Double?,
        avgHeartRate: Double?,
        maxHeartRate: Double?,
        route: [RoutePointDTO],
        heartRateZones: WorkoutHeartRateZones? = nil,
        durationSeconds: Double? = nil,
        distanceMeters: Double? = nil,
        recordedIntervals: [WorkoutRecordedIntervalDTO]? = nil
    ) {
        self.id = id
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.distanceKm = distanceKm
        self.activeEnergyKcal = activeEnergyKcal
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.route = route
        self.heartRateZones = heartRateZones
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.recordedIntervals = recordedIntervals
    }
}
