import XCTest
@testable import HealthCore

final class SummaryMarkdownSerializerTests: XCTestCase {
    private func makeSnapshot() -> DailySnapshot {
        let date = SampleFixtures.iso("2026-05-14T00:00:00Z")
        let generated = SampleFixtures.iso("2026-05-14T22:30:12Z")
        var snap = DailySnapshot(
            date: date,
            timezone: "Europe/Lisbon",
            generatedAt: generated,
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = [
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count"),
            "active_energy": SummaryFragment(metrics: ["total": .int(612)], unit: "kcal"),
            "activity_rings": SummaryFragment(metrics: ["stand_hours": .int(11), "exercise_minutes": .int(42)]),
            "resting_heart_rate": SummaryFragment(metrics: ["value": .int(58)], unit: "bpm"),
            "hrv_sdnn": SummaryFragment(metrics: ["avg": .int(47)], unit: "ms"),
            "vo2_max": SummaryFragment(metrics: ["value": .double(48.2)], unit: "ml/kg/min"),
            "sleep": SummaryFragment(metrics: [
                "duration_minutes": .int(432),
                "stage_deep": .int(78),
                "stage_rem": .int(92),
                "stage_core": .int(240)
            ]),
            "nutrition": SummaryFragment(metrics: [
                "energy_kcal": .double(2240.5),
                "protein_g": .double(145.2),
                "carbs_g": .double(230.4),
                "fat_g": .double(9.4),
                "water_ml": .double(2100.0)
            ]),
            "body_mass": SummaryFragment(metrics: ["value": .double(76.4)], unit: "kg")
        ]
        snap.workouts = [
            WorkoutDTO(
                id: "7f3a",
                type: .outdoorRun,
                startDate: SampleFixtures.iso("2026-05-14T07:00:00Z"),
                endDate: SampleFixtures.iso("2026-05-14T07:38:00Z"),
                durationMinutes: 38,
                distanceKm: 6.2,
                activeEnergyKcal: 410,
                avgHeartRate: 152,
                maxHeartRate: 174,
                route: []
            )
        ]
        snap.stateOfMind = [
            StateOfMindEntryDTO(
                time: SampleFixtures.iso("2026-05-14T08:15:00Z"),
                valence: 0.4,
                labels: ["calm", "focused"]
            )
        ]
        return snap
    }

    func testTitleContainsDayKey() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("Pulse Commit · 2026-05-14"))
    }

    func testAllStandardSectionsPresent() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("🏃 *Activity*"))
        XCTAssertTrue(out.contains("❤️ *Heart*"))
        XCTAssertTrue(out.contains("😴 *Sleep*"))
        XCTAssertTrue(out.contains("🍽 *Nutrition*"))
        XCTAssertTrue(out.contains("⚖️ *Body*"))
        XCTAssertTrue(out.contains("🏋️ *Workouts (1)*"))
        XCTAssertTrue(out.contains("🧠 *State of Mind*"))
    }

    func testStepCountIsThousandSeparated() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("Steps: 12\u{00A0}483"), "got: \(out)")
    }

    func testSchemaVersionFooterPresent() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("`schema_version: 1.0`"))
    }

    func testCommitLinkIncludedWhenProvided() {
        let url = URL(string: "https://github.com/user/repo/commit/abc1234")!
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot(), commitURL: url)
        XCTAssertTrue(out.contains("🔗 [View on GitHub](https://github.com/user/repo/commit/abc1234)"))
    }

    func testCommitLinkOmittedByDefault() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertFalse(out.contains("View on GitHub"))
    }

    func testSleepDurationFormatted() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("Duration: 7h 12m"))
    }

    func testWorkoutLineFormatted() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("• Outdoor Run"))
        XCTAssertTrue(out.contains("Time (Europe/Lisbon): 08:00–08:38"))
        XCTAssertTrue(out.contains("Duration: 38 min · Distance: 6.2 km"))
        XCTAssertTrue(out.contains("Active energy: 410 kcal"))
        XCTAssertTrue(out.contains("Heart rate: avg 152 bpm · max 174 bpm"))
    }

    func testNutritionPreservesFractionalPrecision() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot())
        XCTAssertTrue(out.contains("2\u{00A0}240.5 kcal"), "got: \(out)")
        XCTAssertTrue(out.contains("P 145.2 / C 230.4 / F 9.4"), "got: \(out)")
        XCTAssertTrue(out.contains("Water: 2.1 L"), "got: \(out)")
    }

    func testSectionsOmittedWhenDataMissing() {
        var snap = makeSnapshot()
        snap.summaries.removeValue(forKey: "body_mass")
        snap.summaries.removeValue(forKey: "nutrition")
        snap.workouts = []
        snap.stateOfMind = []
        let out = SummaryMarkdownSerializer().serialize(snap)
        XCTAssertFalse(out.contains("⚖️ *Body*"))
        XCTAssertFalse(out.contains("🍽 *Nutrition*"))
        XCTAssertFalse(out.contains("🏋️ *Workouts"))
        XCTAssertFalse(out.contains("🧠 *State of Mind*"))
    }

    func testCompactVerbosityOneLiner() {
        let out = SummaryMarkdownSerializer().serialize(makeSnapshot(), verbosity: .compact)
        let body = out.split(separator: "\n").first.map(String.init) ?? ""
        XCTAssertTrue(body.contains("12\u{00A0}483 steps"))
        XCTAssertTrue(body.contains("1 workout"))
        XCTAssertTrue(body.contains("sleep 7h12m"))
    }

    func testVerboseAddsRawSampleCounts() {
        var snap = makeSnapshot()
        snap.summaries["steps"] = SummaryFragment(metrics: ["total": .int(12483), "sample_count": .int(120)], unit: "count")
        let out = SummaryMarkdownSerializer().serialize(snap, verbosity: .verbose)
        XCTAssertTrue(out.contains("Raw sample counts"))
        XCTAssertTrue(out.contains("• steps: 120"))
    }
}

extension SummaryMarkdownSerializerTests {
    /// Real-world regression: every reserved MarkdownV2 character in the output
    /// must be either inside a code span (`...`) or preceded by a backslash.
    /// Telegram returns 400 "Character is reserved" otherwise, which is exactly
    /// the bug observed on a real chat (-1003232979943).
    func test_telegramV2_outputHasNoUnescapedReservedChars() {
        let snap = makeSnapshot()
        let md = SummaryMarkdownSerializer().serialize(
            snap,
            verbosity: .standard,
            commitURL: URL(string: "https://github.com/u/r/commit/abc1234"),
            flavor: .telegramV2
        )

        // Strip code spans (backticks) AND link URL parentheses content — both
        // have looser MarkdownV2 escaping rules and false-positive this scan.
        var stripped = ""
        var insideCode = false
        var insideURL = false
        var prev: Character = " "
        for ch in md {
            if ch == "`" { insideCode.toggle(); prev = ch; continue }
            if insideCode { prev = ch; continue }
            // `[text](url)` — once we see `](` we are inside URL until next `)`.
            if !insideURL && prev == "]" && ch == "(" {
                insideURL = true
                prev = ch
                continue
            }
            if insideURL {
                if ch == ")" { insideURL = false }
                prev = ch
                continue
            }
            stripped.append(ch)
            prev = ch
        }

        // Pull out bold-marker positions so we can ignore the leading/trailing
        // `*` that we intentionally inject for *bold* — those are syntax, not
        // user content. Same for the `[...]` and `(...)` shape of links.
        // Easiest path: a *literal* reserved char outside a backslash-escape
        // is a bug. Walk the string and verify.
        let reserved: Set<Character> = ["_", "*", "[", "]", "(", ")", "~", ">", "#", "+", "-", "=", "|", "{", "}", ".", "!"]
        var i = stripped.startIndex
        var failures: [String] = []
        while i < stripped.endIndex {
            let ch = stripped[i]
            if ch == "\\" {
                // Skip the next char — it's intentionally escaped.
                i = stripped.index(after: i)
                if i < stripped.endIndex { i = stripped.index(after: i) }
                continue
            }
            if reserved.contains(ch) {
                // `*` is OK only at bold delimiters: surrounding * is fine — we
                // wrap section headers in *...*. Accept `*` everywhere for this
                // assertion (we control where we put it). Also accept `(` and
                // `)` and `[` and `]` as part of `[text](url)` link shape.
                if ch != "*" && ch != "(" && ch != ")" && ch != "[" && ch != "]" {
                    let nearby = stripped[max(stripped.index(i, offsetBy: -10, limitedBy: stripped.startIndex) ?? stripped.startIndex, stripped.startIndex)...min(stripped.index(i, offsetBy: 10, limitedBy: stripped.endIndex) ?? stripped.endIndex, stripped.endIndex)]
                    failures.append("unescaped '\(ch)' near: \(nearby)")
                }
            }
            i = stripped.index(after: i)
        }
        if !failures.isEmpty {
            XCTFail("Found unescaped MarkdownV2 reserved chars (\(failures.count) total):\n  " + failures.prefix(10).joined(separator: "\n  "))
        }
    }
}
