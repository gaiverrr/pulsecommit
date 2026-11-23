import XCTest

final class AppIconAssetTests: XCTestCase {
    private struct Entry {
        let size: String
        let scale: String
        let idiom: String
        let filename: String
    }

    private func appIconSetURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("PulseCommit/Assets.xcassets/AppIcon.appiconset")
    }

    private func loadEntries() throws -> [Entry] {
        let url = appIconSetURL().appendingPathComponent("Contents.json")
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let images = json["images"] as? [[String: Any]] ?? []
        return images.compactMap { raw in
            guard let size = raw["size"] as? String,
                  let scale = raw["scale"] as? String,
                  let idiom = raw["idiom"] as? String,
                  let filename = raw["filename"] as? String else { return nil }
            return Entry(size: size, scale: scale, idiom: idiom, filename: filename)
        }
    }

    private func pngDimensions(at url: URL) throws -> (width: Int, height: Int) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 24)
        guard header.count == 24 else {
            throw NSError(domain: "AppIconAssetTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG too short: \(url.lastPathComponent)"])
        }
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard Array(header.prefix(8)) == signature else {
            throw NSError(domain: "AppIconAssetTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "not a PNG: \(url.lastPathComponent)"])
        }
        func readUInt32(_ offset: Int) -> Int {
            let bytes = header[offset..<(offset + 4)]
            return bytes.reduce(0) { ($0 << 8) | Int($1) }
        }
        return (readUInt32(16), readUInt32(20))
    }

    private func expectedPixelSize(size: String, scale: String) throws -> (width: Int, height: Int) {
        let sizeParts = size.split(separator: "x").compactMap { Double($0) }
        guard sizeParts.count == 2 else {
            throw NSError(domain: "AppIconAssetTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "bad size: \(size)"])
        }
        let scaleValue = Double(scale.replacingOccurrences(of: "x", with: "")) ?? 1
        let w = Int((sizeParts[0] * scaleValue).rounded())
        let h = Int((sizeParts[1] * scaleValue).rounded())
        return (w, h)
    }

    func test_contentsJson_isParseable_andHasImages() throws {
        let entries = try loadEntries()
        XCTAssertFalse(entries.isEmpty, "Contents.json should declare at least one image")
    }

    func test_everyDeclaredFile_existsOnDisk() throws {
        let folder = appIconSetURL()
        for entry in try loadEntries() {
            let path = folder.appendingPathComponent(entry.filename).path
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), "missing asset file: \(entry.filename)")
        }
    }

    func test_everyPNG_matchesDeclaredPixelDimensions() throws {
        let folder = appIconSetURL()
        for entry in try loadEntries() {
            let url = folder.appendingPathComponent(entry.filename)
            let expected = try expectedPixelSize(size: entry.size, scale: entry.scale)
            let actual = try pngDimensions(at: url)
            XCTAssertEqual(actual.width, expected.width, "\(entry.filename): width \(actual.width) != expected \(expected.width)")
            XCTAssertEqual(actual.height, expected.height, "\(entry.filename): height \(actual.height) != expected \(expected.height)")
        }
    }

    func test_marketingIcon_1024_isPresent() throws {
        let entries = try loadEntries()
        let marketing = entries.first { entry in
            (entry.idiom == "ios-marketing" || entry.idiom == "universal") && entry.size == "1024x1024"
        }
        XCTAssertNotNil(marketing, "App Store 1024×1024 marketing icon entry is missing from Contents.json")
        if let m = marketing {
            let url = appIconSetURL().appendingPathComponent(m.filename)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "1024 marketing icon file missing: \(m.filename)")
            let dim = try pngDimensions(at: url)
            XCTAssertEqual(dim.width, 1024)
            XCTAssertEqual(dim.height, 1024)
        }
    }
}
