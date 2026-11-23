import XCTest
@testable import HealthCore

final class GPXEncoderTests: XCTestCase {
    func testProducesValidGPX11Document() throws {
        let points = [
            RoutePointDTO(
                time: SampleFixtures.iso("2026-05-14T08:00:00Z"),
                latitude: 38.7223,
                longitude: -9.1393,
                elevationMeters: 12.5
            ),
            RoutePointDTO(
                time: SampleFixtures.iso("2026-05-14T08:00:30Z"),
                latitude: 38.7224,
                longitude: -9.1394,
                elevationMeters: nil
            )
        ]
        let data = GPXEncoder().encode(name: "Morning Run", points: points)
        let xml = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(xml.hasPrefix(#"<?xml version="1.0" encoding="UTF-8"?>"#))
        XCTAssertTrue(xml.contains(#"version="1.1""#))
        XCTAssertTrue(xml.contains(#"xmlns="http://www.topografix.com/GPX/1/1""#))
        XCTAssertTrue(xml.contains("<name>Morning Run</name>"))
        XCTAssertTrue(xml.contains(#"<trkpt lat="38.7223" lon="-9.1393">"#))
        XCTAssertTrue(xml.contains("<ele>12.5</ele>"))
        XCTAssertTrue(xml.contains("<time>2026-05-14T08:00:00Z</time>"))
        XCTAssertTrue(xml.contains("<time>2026-05-14T08:00:30Z</time>"))

        // <ele> only emitted when elevation is non-nil — only one in this doc.
        let eleCount = xml.components(separatedBy: "<ele>").count - 1
        XCTAssertEqual(eleCount, 1)
    }

    func testXMLEscapesTrackName() {
        let data = GPXEncoder().encode(name: "Run & <Test>", points: [])
        let xml = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(xml.contains("<name>Run &amp; &lt;Test&gt;</name>"))
    }
}
