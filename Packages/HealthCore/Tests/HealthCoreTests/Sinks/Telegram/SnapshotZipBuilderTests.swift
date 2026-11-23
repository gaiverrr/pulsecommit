import XCTest
import ZIPFoundation
@testable import HealthCore

final class SnapshotZipBuilderTests: XCTestCase {
    func test_build_producesArchiveWithExpectedEntries() throws {
        let files: [FileEntry] = [
            FileEntry(path: "summary.json", data: Data("{\"schema_version\":\"1.0\"}".utf8)),
            FileEntry(path: "summary.md", data: Data("# hi".utf8)),
            FileEntry(path: "samples/steps.json", data: Data("[]".utf8))
        ]

        let zipData = try SnapshotZipBuilder().build(files: files)
        XCTAssertFalse(zipData.isEmpty)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("zipbuilder-test-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try zipData.write(to: tmp)

        let archive = try Archive(url: tmp, accessMode: .read)
        let paths = archive.map { $0.path }.sorted()
        XCTAssertEqual(paths, ["samples/steps.json", "summary.json", "summary.md"])

        guard let entry = archive["summary.md"] else {
            XCTFail("missing summary.md entry")
            return
        }
        var collected = Data()
        _ = try archive.extract(entry) { chunk in collected.append(chunk) }
        XCTAssertEqual(collected, Data("# hi".utf8))
    }

    func test_build_emptyFiles_producesValidArchive() throws {
        let zipData = try SnapshotZipBuilder().build(files: [])
        XCTAssertFalse(zipData.isEmpty)

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("zipbuilder-empty-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try zipData.write(to: tmp)

        let archive = try Archive(url: tmp, accessMode: .read)
        XCTAssertEqual(archive.map { $0.path }.count, 0)
    }
}
