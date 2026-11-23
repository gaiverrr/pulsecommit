import Foundation

public struct SamplesJSONSerializer: Sendable {
    public init() {}

    public func serialize(samplesByCategory: [String: [any SampleDTO]]) throws -> [FileEntry] {
        try samplesByCategory.keys.sorted().map { categoryID in
            let samples = samplesByCategory[categoryID] ?? []
            let payload = SamplesPayload(categoryID: categoryID, samples: samples)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .custom { date, encoder in
                var container = encoder.singleValueContainer()
                try container.encode(SamplesJSONSerializer.iso8601.string(from: date))
            }
            let data = try encoder.encode(payload)
            return FileEntry(path: "samples/\(categoryID).json", data: data)
        }
    }

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

private struct SamplesPayload: Encodable {
    let categoryID: String
    let samples: [any SampleDTO]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case category
        case samples
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(SchemaVersion.current, forKey: .schemaVersion)
        try c.encode(categoryID, forKey: .category)
        try c.encode(samples.map(AnySampleEncodable.init), forKey: .samples)
    }
}

private struct AnySampleEncodable: Encodable {
    let sample: any SampleDTO

    init(_ sample: any SampleDTO) { self.sample = sample }

    func encode(to encoder: Encoder) throws {
        switch sample {
        case let q as QuantitySampleDTO: try q.encode(to: encoder)
        case let w as WorkoutSampleDTO: try w.encode(to: encoder)
        case let s as StateOfMindSampleDTO: try s.encode(to: encoder)
        case let c as CategorySampleDTO: try c.encode(to: encoder)
        default:
            throw EncodingError.invalidValue(
                sample,
                EncodingError.Context(
                    codingPath: encoder.codingPath,
                    debugDescription: "Unsupported SampleDTO concrete type: \(type(of: sample))"
                )
            )
        }
    }
}
