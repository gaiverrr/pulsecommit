import Foundation

public struct CategoryRegistry: Sendable {
    public let all: [any HealthCategory]

    public init(categories: [any HealthCategory]) {
        self.all = categories
    }

    public func category(withId id: String) -> (any HealthCategory)? {
        all.first { $0.id == id }
    }
}
