import XCTest
@testable import HealthCore

final class WristTemperatureBaselineTests: XCTestCase {
    private let today = SampleFixtures.iso("2026-05-14T00:00:00Z")
    private func sample(day: Int, value: Double, source: String = "watch") -> QuantitySampleDTO {
        let end = today.addingTimeInterval(Double(day) * 86400 + 7 * 3600)
        return QuantitySampleDTO(categoryID: "wrist_temperature", startDate: end.addingTimeInterval(-8 * 3600),
                                 endDate: end, value: value, unit: "degC", sourceName: source, sourceBundleID: source)
    }
    private func summarize(_ samples: [QuantitySampleDTO]) throws -> SummaryFragment {
        let result = WristTemperatureBaseline.summaries(samples: samples, from: today,
            to: today.addingTimeInterval(86400), timezone: .gmt)
        return try XCTUnwrap(result.first).fragment
    }
    func test_baselineWeightsNightsEquallyAndExcludesCurrentNight() throws {
        var samples = (-5 ... -1).map { sample(day: $0, value: 36) }
        samples += (0..<20).map { _ in sample(day: -1, value: 37) }
        samples += [sample(day: 0, value: 36.5)]
        let fragment = try summarize(samples)
        XCTAssertEqual(fragment.metrics["baseline_nights"], .int(5))
        XCTAssertEqual(fragment.metrics["baseline_c"], .double(36.19))
        XCTAssertEqual(fragment.metrics["deviation_c"], .double(0.31))
    }
    func test_insufficientHistoryDoesNotInventDeviation() throws {
        let fragment = try summarize((-4 ... 0).map { sample(day: $0, value: 36) })
        XCTAssertEqual(fragment.metrics["avg_c"], .double(36))
        XCTAssertEqual(fragment.metrics["baseline_nights"], .int(4))
        XCTAssertNil(fragment.metrics["deviation_c"])
    }
    func test_oldFutureAndOtherSourceNightsAreExcluded() throws {
        var samples = (-5 ... -1).map { sample(day: $0, value: 36, source: "other") }
        samples += [sample(day: -29, value: 50), sample(day: 1, value: 50), sample(day: 0, value: 36.5)]
        let fragment = try summarize(samples)
        XCTAssertEqual(fragment.metrics["baseline_nights"], .int(0))
        XCTAssertNil(fragment.metrics["deviation_c"])
    }
    func test_emptyAndNonFiniteValuesAreOmitted() {
        XCTAssertTrue(WristTemperatureBaseline.summaries(samples: [sample(day: 0, value: .nan)],
            from: today, to: today.addingTimeInterval(86400), timezone: .gmt).isEmpty)
    }
}
