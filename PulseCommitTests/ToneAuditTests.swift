import XCTest

final class ToneAuditTests: XCTestCase {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static let forbidden: [String] = [
        "seamless",
        "revolutionary",
        "magical",
        "unleash",
        "transform your",
        "your data your way",
        "cutting-edge",
        "harness the power",
        "take control of your",
        "powerful",
        "effortless",
        "delight",
        "delightful",
        "craft",
        "crafted",
    ]

    private static let scanRoots: [String] = [
        "PulseCommit",
        "Packages/HealthCore/Sources",
        "docs/legal",
        "docs/store",
    ]

    private func enumerateFiles(at root: URL) -> [URL] {
        guard let it = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var out: [URL] = []
        for case let url as URL in it {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                out.append(url)
            }
        }
        return out
    }

    private func wordBoundaryMatch(_ word: String, in haystack: String) -> Bool {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return false }
        let range = NSRange(haystack.startIndex..<haystack.endIndex, in: haystack)
        return regex.firstMatch(in: haystack, options: [], range: range) != nil
    }

    func test_userFacingSources_containNoForbiddenToneWords() throws {
        let root = repoRoot()
        var failures: [String] = []

        for relative in Self.scanRoots {
            let dir = root.appendingPathComponent(relative)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }

            for file in enumerateFiles(at: dir) {
                guard let contents = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for word in Self.forbidden where wordBoundaryMatch(word, in: contents) {
                    let rel = file.path.replacingOccurrences(of: root.path + "/", with: "")
                    failures.append("\(rel): forbidden tone word '\(word)'")
                }
            }
        }

        XCTAssertTrue(
            failures.isEmpty,
            "tone audit found forbidden marketing-speak:\n" + failures.joined(separator: "\n")
        )
    }

    func test_verifyToneScriptExistsAndIsExecutable() throws {
        let script = repoRoot().appendingPathComponent("scripts/verify-tone.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: script.path),
                      "scripts/verify-tone.sh must exist")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path),
                      "scripts/verify-tone.sh must be executable")
    }
}
