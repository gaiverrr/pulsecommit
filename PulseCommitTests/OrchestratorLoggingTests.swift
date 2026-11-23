import XCTest

/// pc-apy: regression — Orchestrator (and any source under the wave-5 scope)
/// must use `os.Logger` instead of `NSLog`/`print`/`dump`. NSLog has no
/// privacy markers and dumps everything to the unified log + the device log
/// regardless of build configuration, making accidental token leakage trivial.
final class OrchestratorLoggingTests: XCTestCase {
    func test_orchestratorAndAuthSources_doNotUseNSLogOrPrint() throws {
        let fm = FileManager.default
        var thisFile = URL(fileURLWithPath: #filePath)
        // PulseCommitTests/OrchestratorLoggingTests.swift → repo root.
        thisFile.deleteLastPathComponent()
        thisFile.deleteLastPathComponent()
        let repoRoot = thisFile

        let scopedRelativePaths = [
            "PulseCommit/Orchestrator",
            "PulseCommit/Auth",
            "PulseCommit/Composition/AppContainer+default.swift",
        ]

        var offenders: [String] = []
        for relative in scopedRelativePaths {
            let url = repoRoot.appendingPathComponent(relative)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            let urls: [URL]
            if isDir.boolValue {
                let walker = fm.enumerator(at: url, includingPropertiesForKeys: nil)
                urls = (walker?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
            } else {
                urls = [url]
            }
            for swiftURL in urls {
                let text = (try? String(contentsOf: swiftURL, encoding: .utf8)) ?? ""
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, raw) in lines.enumerated() {
                    let trimmed = raw.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("//") { continue }
                    if trimmed.contains("NSLog(") {
                        offenders.append("\(swiftURL.lastPathComponent):\(index + 1) — NSLog")
                    }
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "wave-5 scope must not call NSLog (use os.Logger). Offenders:\n  \(offenders.joined(separator: "\n  "))"
        )
    }
}
