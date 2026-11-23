import XCTest
@testable import HealthCore

private struct StubCategory: HealthCategory {
    let id: String
    let displayName: String
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { [] }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SummaryFragment(metrics: ["count": .int(samples.count)])
    }
}

final class CategoryRegistryTests: XCTestCase {
    func test_preservesRegistrationOrder() {
        let a = StubCategory(id: "a", displayName: "A")
        let b = StubCategory(id: "b", displayName: "B")
        let c = StubCategory(id: "c", displayName: "C")
        let registry = CategoryRegistry(categories: [a, b, c])

        XCTAssertEqual(registry.all.map(\.id), ["a", "b", "c"])
    }

    func test_lookupById_returnsMatch() {
        let a = StubCategory(id: "steps", displayName: "Steps")
        let b = StubCategory(id: "distance", displayName: "Distance")
        let registry = CategoryRegistry(categories: [a, b])

        XCTAssertEqual(registry.category(withId: "distance")?.id, "distance")
    }

    func test_lookupById_returnsNilForUnknown() {
        let registry = CategoryRegistry(categories: [StubCategory(id: "steps", displayName: "Steps")])
        XCTAssertNil(registry.category(withId: "missing"))
    }

    func test_summarize_routesThroughCategory() {
        let stub = StubCategory(id: "x", displayName: "X")
        let registry = CategoryRegistry(categories: [stub])
        let cat = registry.category(withId: "x")!
        let fragment = cat.summarize([])
        XCTAssertEqual(fragment.metrics["count"], .int(0))
    }
}
