public enum RunProgress: Sendable, Equatable {
    case fetching(day: Int, totalDays: Int)
    case readingSummary(categoryID: String, completed: Int, total: Int)
    case startingSamplesFetch
    case readingSamples(categoryID: String, completed: Int, total: Int)
    case serializing(day: Int, totalDays: Int)
    case delivering(sinkID: String, day: Int, totalDays: Int)
    case retrying(sinkID: String, attempt: Int, totalAttempts: Int, reason: String)
    case finished
}

public typealias RunProgressHandler = @Sendable (RunProgress) async -> Void
