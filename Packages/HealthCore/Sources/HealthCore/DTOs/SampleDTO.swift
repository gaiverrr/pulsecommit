import Foundation

public protocol SampleDTO: Codable, Equatable, Sendable {
    var categoryID: String { get }
    var startDate: Date { get }
    var endDate: Date { get }
    var sourceName: String { get }
    var sourceBundleID: String { get }
}

public struct QuantitySampleDTO: SampleDTO, Hashable {
    public let categoryID: String
    public let startDate: Date
    public let endDate: Date
    public let value: Double
    public let unit: String
    public let sourceName: String
    public let sourceBundleID: String

    public init(
        categoryID: String,
        startDate: Date,
        endDate: Date,
        value: Double,
        unit: String,
        sourceName: String,
        sourceBundleID: String
    ) {
        self.categoryID = categoryID
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.unit = unit
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
    }

    private enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case startDate
        case endDate
        case value
        case unit
        case sourceName
        case sourceBundleID = "sourceBundleId"
    }
}

public struct WorkoutSampleDTO: SampleDTO, Hashable {
    public let categoryID: String
    public let sourceName: String
    public let sourceBundleID: String
    public let workout: WorkoutDTO

    public var startDate: Date { workout.startDate }
    public var endDate: Date { workout.endDate }

    public init(
        categoryID: String,
        sourceName: String,
        sourceBundleID: String,
        workout: WorkoutDTO
    ) {
        self.categoryID = categoryID
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.workout = workout
    }

    private enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case sourceName
        case sourceBundleID = "sourceBundleId"
        case workout
    }
}

public struct StateOfMindSampleDTO: SampleDTO, Hashable {
    public let categoryID: String
    public let sourceName: String
    public let sourceBundleID: String
    public let entry: StateOfMindEntryDTO

    public var startDate: Date { entry.time }
    public var endDate: Date { entry.time }

    public init(
        categoryID: String,
        sourceName: String,
        sourceBundleID: String,
        entry: StateOfMindEntryDTO
    ) {
        self.categoryID = categoryID
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.entry = entry
    }

    private enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case sourceName
        case sourceBundleID = "sourceBundleId"
        case entry
    }
}

public struct CategorySampleDTO: SampleDTO, Hashable {
    public let categoryID: String
    public let startDate: Date
    public let endDate: Date
    public let value: Int
    public let metadata: [String: String]
    public let sourceName: String
    public let sourceBundleID: String

    public init(
        categoryID: String,
        startDate: Date,
        endDate: Date,
        value: Int,
        metadata: [String: String] = [:],
        sourceName: String,
        sourceBundleID: String
    ) {
        self.categoryID = categoryID
        self.startDate = startDate
        self.endDate = endDate
        self.value = value
        self.metadata = metadata
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
    }

    private enum CodingKeys: String, CodingKey {
        case categoryID = "categoryId"
        case startDate
        case endDate
        case value
        case metadata
        case sourceName
        case sourceBundleID = "sourceBundleId"
    }
}
