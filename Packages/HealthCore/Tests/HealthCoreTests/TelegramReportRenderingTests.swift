import XCTest
@testable import HealthCore

/// Telegram-flavor standard/verbose rendering uses a fenced monospace code
/// block so numeric values align. GitHub flavor is unaffected (covered by
/// SummaryMarkdownSerializerTests).
final class TelegramReportRenderingTests: XCTestCase {
    private func makeSnapshot() -> DailySnapshot {
        let date = SampleFixtures.iso("2026-05-14T00:00:00Z")
        var snap = DailySnapshot(
            date: date,
            timezone: "Europe/Lisbon",
            generatedAt: SampleFixtures.iso("2026-05-14T22:30:12Z"),
            deviceName: "iPhone 15 Pro",
            appVersion: "1.0.0"
        )
        snap.summaries = [
            "steps": SummaryFragment(metrics: ["total": .int(12483)], unit: "count"),
            "active_energy": SummaryFragment(metrics: ["total": .int(612)], unit: "kcal"),
            "resting_heart_rate": SummaryFragment(metrics: ["value": .int(58)], unit: "bpm"),
            "sleep": SummaryFragment(metrics: ["duration_minutes": .int(432)])
        ]
        return snap
    }

    private func render(_ snap: DailySnapshot, commitURL: URL? = nil) -> String {
        SummaryMarkdownSerializer().serialize(
            snap,
            verbosity: .standard,
            commitURL: commitURL,
            flavor: .telegramV2
        )
    }

    /// Split the message into (beforeFence, insideFence, afterFence).
    private func fenceParts(_ md: String) -> (before: String, inside: String, after: String)? {
        let parts = md.components(separatedBy: "```")
        guard parts.count == 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    func test_standardTelegram_wrapsDataInSingleCodeBlock() {
        let md = render(makeSnapshot())
        let occurrences = md.components(separatedBy: "```").count - 1
        XCTAssertEqual(occurrences, 2, "exactly one fenced code block (open+close):\n\(md)")
    }

    func test_titleStaysBoldOutsideTheFence() {
        let md = render(makeSnapshot())
        guard let parts = fenceParts(md) else { return XCTFail("no fence: \(md)") }
        XCTAssertTrue(parts.before.contains("*Pulse Commit · 2026\\-05\\-14*"), "got before: \(parts.before)")
    }

    func test_schemaFooterAndLinkStayOutsideTheFence() {
        let url = URL(string: "https://github.com/u/r/commit/abc1234")!
        let md = render(makeSnapshot(), commitURL: url)
        guard let parts = fenceParts(md) else { return XCTFail("no fence: \(md)") }
        XCTAssertTrue(parts.after.contains("`schema_version: 1.0`"), "got after: \(parts.after)")
        XCTAssertTrue(parts.after.contains("[View on GitHub]"), "got after: \(parts.after)")
        XCTAssertFalse(parts.inside.contains("schema_version"), "schema must not be inside the block")
    }

    func test_noEmojiInsideTheFence() {
        let md = render(makeSnapshot())
        guard let parts = fenceParts(md) else { return XCTFail("no fence: \(md)") }
        for emoji in ["🏃", "❤️", "😴", "🫀", "🔗"] {
            XCTAssertFalse(parts.inside.contains(emoji), "emoji \(emoji) breaks monospace alignment")
        }
    }

    func test_valuesAreColumnAligned() {
        let md = render(makeSnapshot())
        guard let parts = fenceParts(md) else { return XCTFail("no fence: \(md)") }
        let lines = parts.inside.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let stepsLine = lines.first(where: { $0.contains("Steps") }),
              let rhrLine = lines.first(where: { $0.contains("Resting HR") }) else {
            return XCTFail("missing rows: \(parts.inside)")
        }
        // The value column must start at the same character offset on both rows.
        guard let stepsValue = stepsLine.range(of: "12\u{00A0}483"),
              let rhrValue = rhrLine.range(of: "58") else {
            return XCTFail("values not found:\n\(stepsLine)\n\(rhrLine)")
        }
        let stepsCol = stepsLine.distance(from: stepsLine.startIndex, to: stepsValue.lowerBound)
        let rhrCol = rhrLine.distance(from: rhrLine.startIndex, to: rhrValue.lowerBound)
        XCTAssertEqual(stepsCol, rhrCol, "value columns misaligned:\n[\(stepsLine)]\n[\(rhrLine)]")
    }

    func test_sectionTitlesPresentInsideFence() {
        let md = render(makeSnapshot())
        guard let parts = fenceParts(md) else { return XCTFail("no fence: \(md)") }
        XCTAssertTrue(parts.inside.contains("Activity"))
        XCTAssertTrue(parts.inside.contains("Heart"))
        XCTAssertTrue(parts.inside.contains("Sleep"))
    }

    func test_compactTelegram_isStillASingleLineNoFence() {
        let md = SummaryMarkdownSerializer().serialize(makeSnapshot(), verbosity: .compact, flavor: .telegramV2)
        XCTAssertFalse(md.contains("```"), "compact stays a one-liner, no code block")
    }

    func test_hrvMeasurementCountAppearsNextToAverageInStandardAndVerbose() throws {
        for verbosity in [SummaryVerbosity.standard, .verbose] {
            for count in [1, 2, 20] {
                var snap = makeSnapshot()
                snap.summaries["hrv_sdnn"] = SummaryFragment(
                    metrics: ["avg": .int(47), "sample_count": .int(count)], unit: "ms"
                )
                let md = SummaryMarkdownSerializer().serialize(snap, verbosity: verbosity, flavor: .telegramV2)
                let body = try XCTUnwrap(fenceParts(md)).inside
                let row = try XCTUnwrap(body.split(separator: "\n").first { $0.contains("HRV (SDNN)") })
                XCTAssertTrue(row.hasSuffix("47 ms · \(count) measurement\(count == 1 ? "" : "s")"), "\(row)")
            }
        }
    }

    func test_hrvWithoutMeasurementCountStillShowsAverage() throws {
        var snap = makeSnapshot()
        snap.summaries["hrv_sdnn"] = SummaryFragment(metrics: ["avg": .int(47)], unit: "ms")
        let body = try XCTUnwrap(fenceParts(render(snap))).inside
        let row = try XCTUnwrap(body.split(separator: "\n").first { $0.contains("HRV (SDNN)") })
        XCTAssertTrue(row.hasSuffix("47 ms"))
        XCTAssertFalse(row.contains("measurement"))
    }

    func test_hrvWithoutAverageDoesNotInventAReading() {
        var snap = makeSnapshot()
        snap.summaries["hrv_sdnn"] = SummaryFragment(metrics: ["sample_count": .int(0)], unit: "ms")
        let md = render(snap)
        XCTAssertFalse(md.contains("HRV (SDNN)"))
        XCTAssertFalse(md.contains("measurement"))
    }

    func test_standardGitHubKeepsExistingHRVRow() {
        var snap = makeSnapshot()
        snap.summaries["hrv_sdnn"] = SummaryFragment(
            metrics: ["avg": .int(47), "sample_count": .int(20)], unit: "ms"
        )
        let md = SummaryMarkdownSerializer().serialize(snap, flavor: .github)
        XCTAssertTrue(md.contains("• HRV (SDNN): 47 ms\n"))
        XCTAssertFalse(md.contains("measurements"))
    }
    func test_sleepDetailsAndRespiratoryRateUseSnapshotTimezone() {
        var snap = makeSnapshot()
        snap.summaries["sleep"] = SummaryFragment(metrics: [
            "duration_minutes": .int(432), "stage_awake": .int(18),
            "sleep_start": .string("2026-05-13T22:30:00Z"),
            "sleep_end": .string("2026-05-14T06:00:00Z")
        ])
        snap.summaries["respiratory_rate"] = SummaryFragment(metrics: ["sleep_avg": .double(14.5)], unit: "breaths/min")
        let md = render(snap)
        XCTAssertTrue(md.contains("23:30"))
        XCTAssertTrue(md.contains("07:00"))
        XCTAssertTrue(md.contains("Awake"))
        XCTAssertTrue(md.contains("18 min"))
        XCTAssertTrue(md.contains("14.5 breaths/min"))
    }

    func test_telegramWorkoutsShowMaximumHeartRateWhenAvailable() {
        var snap = makeSnapshot()
        snap.workouts = [WorkoutDTO(
            id: "run", type: .outdoorRun, startDate: snap.date, endDate: snap.date,
            durationMinutes: 38, distanceKm: 6.2, activeEnergyKcal: nil,
            avgHeartRate: 152, maxHeartRate: 174, route: []
        )]
        XCTAssertTrue(render(snap).contains("Heart rate: avg 152 bpm · max 174 bpm"))
    }

    func test_standardAndVerboseShowPrecisePausedWorkoutDetailsAndCapRecordedEvents() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-05-14T22:45:00Z")
        func interval(_ kind: WorkoutRecordedIntervalDTO.Kind, startOffset: TimeInterval, duration: TimeInterval) -> WorkoutRecordedIntervalDTO {
            WorkoutRecordedIntervalDTO(
                kind: kind,
                startDate: start.addingTimeInterval(startOffset),
                endDate: start.addingTimeInterval(startOffset + duration),
                durationSeconds: duration
            )
        }
        let laps: [WorkoutRecordedIntervalDTO] = (0..<6).map { index in
            interval(.lap, startOffset: Double(index) * 300, duration: 300)
        }
        let segments: [WorkoutRecordedIntervalDTO] = (0..<5).map { index in
            interval(.segment, startOffset: 120 + Double(index) * 180, duration: 300)
        }
        let intervals = laps + segments
        snap.workouts = [WorkoutDTO(
            id: "run", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(3_900), durationMinutes: 60,
            distanceKm: 10, activeEnergyKcal: 612, avgHeartRate: 152,
            maxHeartRate: 176, route: [], durationSeconds: 3_599.5,
            distanceMeters: 10_000, recordedIntervals: intervals
        )]

        for verbosity in [SummaryVerbosity.standard, .verbose] {
            let markdown = SummaryMarkdownSerializer().serialize(snap, verbosity: verbosity, flavor: .telegramV2)
            XCTAssertTrue(markdown.contains("Time (Europe/Lisbon): 23:45–00:50"), markdown)
            XCTAssertTrue(markdown.contains("Duration: 59m 59.5s · Distance: 10 km"), markdown)
            XCTAssertTrue(markdown.contains("Avg pace: 6:00/km · Active energy: 612 kcal"), markdown)
            XCTAssertTrue(markdown.contains("Heart rate: avg 152 bpm · max 176 bpm"), markdown)
            XCTAssertTrue(markdown.contains("Recorded laps (6, elapsed)"), markdown)
            XCTAssertTrue(markdown.contains("2 more laps"), markdown)
            XCTAssertTrue(markdown.contains("Recorded segments (5, elapsed)"), markdown)
            XCTAssertTrue(markdown.contains("1 more segment"), markdown)
            XCTAssertEqual(markdown.components(separatedBy: "Lap ").count - 1, 4, markdown)
            XCTAssertEqual(markdown.components(separatedBy: "Segment ").count - 1, 4, markdown)
        }
    }

    func test_parallelKilometerAndMileSplitsShowOneSeries() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-11-23T18:44:10Z")
        func split(_ startOffset: TimeInterval, _ duration: TimeInterval) -> WorkoutRecordedIntervalDTO {
            WorkoutRecordedIntervalDTO(
                kind: .segment,
                startDate: start.addingTimeInterval(startOffset),
                endDate: start.addingTimeInterval(startOffset + duration),
                durationSeconds: duration
            )
        }
        let kilometers = (0..<17).map { split(Double($0) * 325, 325) }
        let miles = (0..<10).map { split(Double($0) * 523, 523) }
        let interleaved = zip(kilometers, miles).flatMap { [$0, $1] } + kilometers.dropFirst(10)
        snap.workouts = [WorkoutDTO(
            id: "run", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(5_600), durationMinutes: 92,
            distanceKm: 17, activeEnergyKcal: 1_209, avgHeartRate: 125,
            maxHeartRate: 170, route: [], durationSeconds: 5_528.9,
            distanceMeters: 17_000, recordedIntervals: interleaved
        )]

        let markdown = SummaryMarkdownSerializer().serialize(snap, verbosity: .standard, flavor: .telegramV2)

        XCTAssertTrue(markdown.contains("Recorded segments (17 km splits, elapsed)"), markdown)
        XCTAssertTrue(markdown.contains("+13 more segments in JSON"), markdown)
        XCTAssertTrue(markdown.contains("+10 segments from an overlapping series in JSON"), markdown)
        XCTAssertTrue(markdown.contains("Segment 2: 18:49:35–18:55:00 · 5m 25s"), markdown)
        XCTAssertFalse(markdown.contains("8m 43s"), markdown)
    }

    func test_fiveKilometerAlertSeriesDoesNotStealKilometerSplits() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-11-23T18:44:10Z")
        func split(_ startOffset: TimeInterval, _ duration: TimeInterval) -> WorkoutRecordedIntervalDTO {
            WorkoutRecordedIntervalDTO(
                kind: .segment,
                startDate: start.addingTimeInterval(startOffset),
                endDate: start.addingTimeInterval(startOffset + duration),
                durationSeconds: duration
            )
        }
        let kilometers = (0..<15).map { split(Double($0) * 300, 300) }
        let fiveKilometers = (0..<3).map { split(Double($0) * 1_500, 1_500) }
        snap.workouts = [WorkoutDTO(
            id: "run", type: .outdoorRun, startDate: start,
            endDate: start.addingTimeInterval(4_500), durationMinutes: 75,
            distanceKm: 15, activeEnergyKcal: 1_000, avgHeartRate: 140,
            maxHeartRate: 170, route: [], durationSeconds: 4_500,
            distanceMeters: 15_000, recordedIntervals: fiveKilometers + kilometers
        )]

        let markdown = SummaryMarkdownSerializer().serialize(snap, verbosity: .standard, flavor: .telegramV2)

        XCTAssertTrue(markdown.contains("Recorded segments (15 km splits, elapsed)"), markdown)
        XCTAssertTrue(markdown.contains("+3 segments from an overlapping series in JSON"), markdown)
        XCTAssertFalse(markdown.contains("25m"), markdown)
    }

    func test_lapSetsSeparatedByRestsStayFullyListed() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-11-23T07:00:00Z")
        func lap(_ startOffset: TimeInterval) -> WorkoutRecordedIntervalDTO {
            WorkoutRecordedIntervalDTO(
                kind: .lap,
                startDate: start.addingTimeInterval(startOffset),
                endDate: start.addingTimeInterval(startOffset + 60),
                durationSeconds: 60
            )
        }
        let firstSet = (0..<3).map { lap(Double($0) * 60) }
        let secondSet = (0..<3).map { lap(300 + Double($0) * 60) }
        snap.workouts = [WorkoutDTO(
            id: "swim", type: .swimming, startDate: start,
            endDate: start.addingTimeInterval(600), durationMinutes: 10,
            distanceKm: 0.6, activeEnergyKcal: 90, avgHeartRate: 130,
            maxHeartRate: 150, route: [], durationSeconds: 600,
            distanceMeters: 600, recordedIntervals: firstSet + secondSet
        )]

        let markdown = SummaryMarkdownSerializer().serialize(snap, verbosity: .standard, flavor: .telegramV2)

        XCTAssertTrue(markdown.contains("Recorded laps (6, elapsed)"), markdown)
        XCTAssertTrue(markdown.contains("+2 more laps in JSON"), markdown)
        XCTAssertFalse(markdown.contains("overlapping"), markdown)
    }

    func test_githubShowsEquivalentCyclingDetailsWhileCompactStaysCompact() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-05-14T10:00:00Z")
        snap.workouts = [WorkoutDTO(
            id: "ride", type: .outdoorCycling, startDate: start,
            endDate: start.addingTimeInterval(3_600), durationMinutes: 60,
            distanceKm: 30, activeEnergyKcal: 500, avgHeartRate: 140,
            maxHeartRate: 168, route: [], durationSeconds: 3_600,
            distanceMeters: 30_000
        )]

        let github = SummaryMarkdownSerializer().serialize(snap, flavor: .github)
        XCTAssertTrue(github.contains("Time (Europe/Lisbon): 11:00–12:00"), github)
        XCTAssertTrue(github.contains("Avg speed: 30 km/h"), github)
        XCTAssertTrue(github.contains("max 168 bpm"), github)

        let compact = SummaryMarkdownSerializer().serialize(snap, verbosity: .compact, flavor: .telegramV2)
        XCTAssertFalse(compact.contains("Avg speed"), compact)
        XCTAssertFalse(compact.contains("Active energy"), compact)
        XCTAssertFalse(compact.contains("Recorded"), compact)
    }

    func test_hugeFiniteValuesDoNotOverflowOrProduceEmptyPace() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-05-14T10:00:00Z")
        snap.workouts = [WorkoutDTO(
            id: "huge", type: .walking, startDate: start,
            endDate: start.addingTimeInterval(60), durationMinutes: 1,
            distanceKm: 1, activeEnergyKcal: nil, avgHeartRate: .greatestFiniteMagnitude,
            maxHeartRate: nil, route: [], durationSeconds: .greatestFiniteMagnitude,
            distanceMeters: 1
        )]

        let markdown = render(snap)

        XCTAssertTrue(markdown.contains("Duration: 1 min"), markdown)
        XCTAssertFalse(markdown.contains("Avg pace: /km"), markdown)
        XCTAssertFalse(markdown.contains("Heart rate"), markdown)
    }

    func test_preciseDurationCarriesRoundedSecondsIntoMinutesAndHours() {
        var snap = makeSnapshot()
        let start = SampleFixtures.iso("2026-05-14T10:00:00Z")
        snap.workouts = [WorkoutDTO(
            id: "boundary", type: .walking, startDate: start,
            endDate: start.addingTimeInterval(3_600), durationMinutes: 59,
            distanceKm: nil, activeEnergyKcal: nil, avgHeartRate: nil,
            maxHeartRate: nil, route: [], durationSeconds: 3_599.999
        )]

        let markdown = render(snap)

        XCTAssertTrue(markdown.contains("Duration: 1h 0m 0s"), markdown)
        XCTAssertFalse(markdown.contains("60s"), markdown)
    }

    func test_reportShowsGenerationTimeAndLatestSampleSeparately() {
        var snap = makeSnapshot()
        snap.latestSampleAt = SampleFixtures.iso("2026-05-14T20:10:00Z")
        for verbosity in SummaryVerbosity.allCases {
            let md = SummaryMarkdownSerializer().serialize(snap, verbosity: verbosity, flavor: .telegramV2)
            XCTAssertTrue(md.contains("Generated"))
            XCTAssertTrue(md.contains("23:30"))
            XCTAssertTrue(md.contains("Latest sample"))
            XCTAssertTrue(md.contains("21:10"))
            XCTAssertTrue(md.contains("Europe/Lisbon"))
        }
    }

    func test_missingOptionalDataDoesNotProduceZeroOrMadeUpValues() {
        let md = render(makeSnapshot())
        XCTAssertFalse(md.contains("Latest sample"))
        XCTAssertFalse(md.contains("breaths/min"))
        XCTAssertFalse(md.contains("max HR"))
        XCTAssertFalse(md.contains("Fell asleep"))
    }

}
