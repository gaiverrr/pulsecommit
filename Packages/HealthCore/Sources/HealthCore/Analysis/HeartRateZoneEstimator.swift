import Foundation

public struct HeartRateZoneConfiguration: Equatable, Hashable, Sendable {
    public let lowerBoundsBPM: [Int]

    public init?(lowerBoundsBPM: [Int]) {
        guard lowerBoundsBPM.count == 4,
              lowerBoundsBPM.allSatisfy({ (1...300).contains($0) }),
              zip(lowerBoundsBPM, lowerBoundsBPM.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        self.lowerBoundsBPM = lowerBoundsBPM
    }
}

public struct WorkoutHeartRateZones: Codable, Equatable, Hashable, Sendable {
    public let lowerBoundsBPM: [Int]
    public let secondsByZone: [Double]
    public let activeSeconds: Double
    public let method: String
    public var coveredSeconds: Double { secondsByZone.reduce(0, +) }

    enum CodingKeys: String, CodingKey {
        case lowerBoundsBPM = "lower_bounds_bpm"
        case secondsByZone = "seconds_by_zone"
        case activeSeconds = "active_seconds"
        case method
    }
}

public enum HeartRateZoneEstimator {
    public static func estimate(
        samples: [QuantitySampleDTO], configuration: HeartRateZoneConfiguration,
        workout: DateInterval, activeIntervals: [DateInterval]
    ) -> WorkoutHeartRateZones? {
        guard workout.duration > 0 else { return nil }
        let valid = samples.filter {
            $0.value.isFinite && $0.value > 0 && $0.startDate >= workout.start && $0.startDate < workout.end
        }
        let points = Dictionary(grouping: valid, by: \.startDate).map { date, samples in
            (date: date, bpm: samples.reduce(0.0) { $0 + $1.value } / Double(samples.count))
        }.sorted { $0.date < $1.date }
        let active = merged(activeIntervals.compactMap { interval in
            let start = max(interval.start, workout.start)
            let end = min(interval.end, workout.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        })
        var seconds = Array(repeating: 0.0, count: 5)
        for (index, point) in points.enumerated() {
            let next = index + 1 < points.count ? points[index + 1].date : workout.end
            // Point readings only support an estimate between observations.
            // Limit forward hold to 30 s so long gaps never look measured.
            let end = min(next, point.date.addingTimeInterval(30), workout.end)
            let zone = configuration.lowerBoundsBPM.filter { point.bpm >= Double($0) }.count
            // Never carry a pre-pause or paused reading into a resumed interval.
            if let interval = active.first(where: { point.date >= $0.start && point.date < $0.end }) {
                seconds[zone] += max(0, min(end, interval.end).timeIntervalSince(point.date))
            }
        }
        guard seconds.reduce(0, +) > 0 else { return nil }
        return WorkoutHeartRateZones(lowerBoundsBPM: configuration.lowerBoundsBPM, secondsByZone: seconds,
                                    activeSeconds: active.reduce(0) { $0 + $1.duration },
                                    method: "custom_thresholds_forward_hold_max_30s")
    }

    private static func merged(_ intervals: [DateInterval]) -> [DateInterval] {
        var result: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) {
            if let last = result.last, interval.start <= last.end {
                result[result.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                result.append(interval)
            }
        }
        return result
    }
}

extension WorkoutHeartRateZones {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let bounds = try c.decode([Int].self, forKey: .lowerBoundsBPM)
        let seconds = try c.decode([Double].self, forKey: .secondsByZone)
        let active = try c.decode(Double.self, forKey: .activeSeconds)
        let method = try c.decode(String.self, forKey: .method)
        guard HeartRateZoneConfiguration(lowerBoundsBPM: bounds) != nil,
              seconds.count == 5, seconds.allSatisfy({ $0.isFinite && $0 >= 0 }),
              active.isFinite, active >= 0, seconds.reduce(0, +) <= active + 0.001 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid heart-rate zone data"))
        }
        self.init(lowerBoundsBPM: bounds, secondsByZone: seconds, activeSeconds: active, method: method)
    }
}
