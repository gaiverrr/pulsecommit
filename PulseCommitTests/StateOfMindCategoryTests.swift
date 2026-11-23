import XCTest
import HealthCore
@testable import PulseCommit

final class StateOfMindCategoryTests: XCTestCase {
    private let store = NullStore()

    private func sample(valence: Double, at time: Date, labels: [String] = []) -> StateOfMindSampleDTO {
        StateOfMindSampleDTO(
            categoryID: "state_of_mind",
            sourceName: "Test",
            sourceBundleID: "test.bundle",
            entry: StateOfMindEntryDTO(time: time, valence: valence, labels: labels)
        )
    }

    func test_id_isStable() {
        XCTAssertEqual(StateOfMindCategory(store: store).id, "state_of_mind")
    }

    func test_summarize_emptyProducesZeroCountAndValence() {
        let cat = StateOfMindCategory(store: store)
        let frag = cat.summarize([])
        XCTAssertEqual(frag.metrics["count"], .int(0))
        XCTAssertEqual(frag.metrics["avg_valence"], .double(0))
        XCTAssertEqual(frag.unit, "entries")
    }

    func test_summarize_averagesValenceAcrossTwoEntries() {
        let cat = StateOfMindCategory(store: store)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let samples: [any SampleDTO] = [
            sample(valence: 0.5, at: base, labels: ["happy"]),
            sample(valence: -0.1, at: base.addingTimeInterval(3600), labels: ["calm"])
        ]
        let frag = cat.summarize(samples)
        XCTAssertEqual(frag.metrics["count"], .int(2))
        XCTAssertEqual(frag.metrics["avg_valence"], .double(0.2))
    }
}
