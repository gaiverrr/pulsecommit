import Foundation
import ZIPFoundation

public struct SnapshotZipBuilder {
    public init() {}

    public func build(files: [FileEntry]) throws -> Data {
        let fm = FileManager.default
        let tmpURL = fm.temporaryDirectory.appendingPathComponent("pulse-commit-\(UUID().uuidString).zip")
        defer { try? fm.removeItem(at: tmpURL) }

        let archive = try Archive(url: tmpURL, accessMode: .create)

        for entry in files {
            let data = entry.data
            try archive.addEntry(
                with: entry.path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    let end = min(start + size, data.count)
                    return data.subdata(in: start..<end)
                }
            )
        }

        return try Data(contentsOf: tmpURL)
    }
}
