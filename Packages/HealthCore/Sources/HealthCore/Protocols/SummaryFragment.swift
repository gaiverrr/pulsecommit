import Foundation

public enum MetricValue: Codable, Equatable, Hashable, Sendable {
    case int(Int)
    case double(Double)
    case string(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let v = try? c.decode(Int.self) { self = .int(v); return }
        if let v = try? c.decode(Double.self) { self = .double(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "MetricValue: unsupported type")
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        }
    }
}

public struct SummaryFragment: Codable, Equatable, Hashable, Sendable {
    public var metrics: [String: MetricValue]
    public var unit: String?

    public init(metrics: [String: MetricValue] = [:], unit: String? = nil) {
        self.metrics = metrics
        self.unit = unit
    }
}
