import Foundation

public enum SummaryVerbosity: String, Sendable, Equatable, CaseIterable {
    case compact
    case standard
    case verbose
}

public enum MarkdownFlavor: Sendable, Equatable {
    case github
    case telegramV2
}

public struct SummaryMarkdownSerializer: Sendable {
    public init() {}

    public func serialize(
        _ snapshot: DailySnapshot,
        verbosity: SummaryVerbosity = .standard,
        commitURL: URL? = nil,
        flavor: MarkdownFlavor = .github
    ) -> String {
        switch verbosity {
        case .compact:
            return renderCompact(snapshot, commitURL: commitURL, flavor: flavor)
        case .standard:
            if flavor == .telegramV2 {
                return renderTelegramReport(snapshot, commitURL: commitURL, includeRawCounts: false)
            }
            return renderStandard(snapshot, commitURL: commitURL, includeRawCounts: false, flavor: flavor)
        case .verbose:
            if flavor == .telegramV2 {
                return renderTelegramReport(snapshot, commitURL: commitURL, includeRawCounts: true)
            }
            return renderStandard(snapshot, commitURL: commitURL, includeRawCounts: true, flavor: flavor)
        }
    }

    // MARK: - Telegram monospace report

    /// Telegram renders fenced code blocks in a monospace font, so we lay the
    /// metrics out as an aligned report (values share a start column). Bold,
    /// inline code, and links do not render inside a fence, so the title,
    /// schema footer, and GitHub link stay outside it.
    private func renderTelegramReport(
        _ snapshot: DailySnapshot,
        commitURL: URL?,
        includeRawCounts: Bool
    ) -> String {
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        var out: [String] = ["🫀 *Pulse Commit · \(e(dayKey, .telegramV2))*"]

        let body = telegramReportBody(snapshot, includeRawCounts: includeRawCounts)
        if !body.isEmpty {
            out.append("```")
            out.append(body)
            out.append("```")
        }

        out.append(contentsOf: telegramFreshnessLines(snapshot))
        out.append("`schema_version: \(snapshot.schemaVersion)`")
        if let url = commitURL {
            out.append("🔗 [View on GitHub](\(eu(url, .telegramV2)))")
        }
        return out.joined(separator: "\n")
    }

    private func telegramReportBody(_ snapshot: DailySnapshot, includeRawCounts: Bool) -> String {
        typealias Row = (label: String, value: String)
        let indent = "  "
        let gap = 2

        // Sections whose rows share one global value column.
        var aligned: [(title: String, rows: [Row])] = []

        var activity: [Row] = []
        if let steps = stepCount(snapshot) { activity.append(("Steps", formatThousands(steps))) }
        if let active = doubleMetric(snapshot, category: "active_energy", key: "total") {
            activity.append(("Active energy", "\(formatNumber(active)) kcal"))
        }
        if let rings = snapshot.summaries["activity_rings"] {
            var parts: [String] = []
            if let stand = intMetric(rings, "stand_hours") { parts.append("Stand \(stand)h") }
            if let ex = intMetric(rings, "exercise_minutes") { parts.append("Exercise \(ex)m") }
            if !parts.isEmpty { activity.append(("Rings", parts.joined(separator: " · "))) }
        }
        if !activity.isEmpty { aligned.append(("Activity", activity)) }

        var heart: [Row] = []
        if let rhr = intMetric(snapshot.summaries["resting_heart_rate"], "value") { heart.append(("Resting HR", "\(rhr) bpm")) }
        if let hrv = intMetric(snapshot.summaries["hrv_sdnn"], "avg") {
            var value = "\(hrv) ms"
            if let count = intMetric(snapshot.summaries["hrv_sdnn"], "sample_count"), count > 0 {
                value += " · \(count) measurement\(count == 1 ? "" : "s")"
            }
            heart.append(("HRV (SDNN)", value))
        }
        if let vo2 = doubleMetric(snapshot.summaries["vo2_max"], "value") { heart.append(("VO₂ max", formatNumber(vo2))) }
        if !heart.isEmpty { aligned.append(("Heart", heart)) }

        if let sleep = snapshot.summaries["sleep"] {
            var rows: [Row] = []
            if let mins = intMetric(sleep, "duration_minutes") { rows.append(("Duration", formatHoursMinutes(mins))) }
            var stageParts: [String] = []
            if let m = intMetric(sleep, "stage_deep") { stageParts.append("Deep \(formatHoursMinutesCompact(m))") }
            if let m = intMetric(sleep, "stage_rem") { stageParts.append("REM \(formatHoursMinutesCompact(m))") }
            if let m = intMetric(sleep, "stage_core") { stageParts.append("Core \(formatHoursMinutesCompact(m))") }
            if !stageParts.isEmpty { rows.append(("Stages", stageParts.joined(separator: " · "))) }
            if let awake = intMetric(sleep, "stage_awake") { rows.append(("Awake", "\(awake) min")) }
            if let start = dateMetric(sleep, "sleep_start") { rows.append(("Fell asleep", localTimestamp(start, snapshot: snapshot))) }
            if let end = dateMetric(sleep, "sleep_end") { rows.append(("Woke up", localTimestamp(end, snapshot: snapshot))) }
            if !rows.isEmpty { aligned.append(("Sleep", rows)) }
        }

        if let respiratory = doubleMetric(snapshot.summaries["respiratory_rate"], "sleep_avg") {
            aligned.append(("Sleep breathing", [("Respiratory rate", "\(formatNumber(respiratory)) breaths/min")]))
        }

        if let nutrition = snapshot.summaries["nutrition"] {
            var rows: [Row] = []
            if let kcal = doubleMetric(nutrition, "energy_kcal") { rows.append(("Energy", "\(formatDecimal(kcal)) kcal")) }
            let p = doubleMetric(nutrition, "protein_g")
            let c = doubleMetric(nutrition, "carbs_g")
            let f = doubleMetric(nutrition, "fat_g")
            if let p, let c, let f {
                rows.append(("Macros", "P \(formatNumber(p)) / C \(formatNumber(c)) / F \(formatNumber(f))"))
            }
            if let water = doubleMetric(nutrition, "water_ml") { rows.append(("Water", "\(formatNumber(water / 1000)) L")) }
            if !rows.isEmpty { aligned.append(("Nutrition", rows)) }
        }

        if let weight = doubleMetric(snapshot.summaries["body_mass"], "value") {
            aligned.append(("Body", [("Weight", "\(formatNumber(weight)) kg")]))
        }

        if let temperature = snapshot.summaries["wrist_temperature"],
           let average = doubleMetric(temperature, "avg_c") {
            var rows: [Row] = [("Sleeping temp", "\(formatTemperature(average)) °C")]
            if let delta = doubleMetric(temperature, "deviation_c"),
               let baseline = doubleMetric(temperature, "baseline_c"),
               let nights = intMetric(temperature, "baseline_nights") {
                rows.append(("Change", "\(delta >= 0 ? "+" : "")\(formatTemperature(delta)) °C"))
                rows.append(("Baseline", "PulseCommit: \(formatTemperature(baseline)) °C · \(nights) nights / 28d"))
            } else if let nights = intMetric(temperature, "baseline_nights") {
                rows.append(("Baseline", "PulseCommit: \(nights) of 5 nights · last 28d"))
            }
            aligned.append(("Wrist temperature", rows))
        }

        let labelWidth = aligned.flatMap { $0.rows }.map { $0.label.count }.max() ?? 0

        func alignedBlock(_ title: String, _ rows: [Row]) -> String {
            var lines = [title]
            for row in rows {
                let pad = String(repeating: " ", count: max(0, labelWidth - row.label.count) + gap)
                lines.append("\(indent)\(MarkdownV2Escaper.escapeCodeContent(row.label))\(pad)\(MarkdownV2Escaper.escapeCodeContent(row.value))")
            }
            return lines.joined(separator: "\n")
        }

        var blocks: [String] = aligned.map { alignedBlock($0.title, $0.rows) }

        // Workouts and State of Mind are event lists, not metric tables — free
        // lines under their title rather than the aligned value column.
        if !snapshot.workouts.isEmpty {
            var lines = ["Workouts (\(snapshot.workouts.count))"]
            for w in snapshot.workouts {
                for (index, line) in workoutDetailLines(w, snapshot: snapshot).enumerated() {
                    let lineIndent = index == 0 ? indent : indent + indent
                    lines.append(lineIndent + MarkdownV2Escaper.escapeCodeContent(line))
                }
            }
            blocks.append(lines.joined(separator: "\n"))
        }

        if !snapshot.stateOfMind.isEmpty {
            let labels = snapshot.stateOfMind.flatMap { $0.labels }
            let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? []
            blocks.append("State of Mind\n" + indent + MarkdownV2Escaper.escapeCodeContent(unique.joined(separator: ", ")))
        }

        if includeRawCounts {
            var rows: [Row] = []
            for k in snapshot.summaries.keys.sorted() {
                if let count = intMetric(snapshot.summaries[k], "sample_count") {
                    rows.append((k, String(count)))
                }
            }
            if !rows.isEmpty {
                let w = rows.map { $0.label.count }.max() ?? 0
                var lines = ["Raw sample counts"]
                for r in rows {
                    let pad = String(repeating: " ", count: max(0, w - r.label.count) + gap)
                    lines.append("\(indent)\(MarkdownV2Escaper.escapeCodeContent(r.label))\(pad)\(r.value)")
                }
                blocks.append(lines.joined(separator: "\n"))
            }
        }

        return blocks.joined(separator: "\n\n")
    }

    private func e(_ s: String, _ flavor: MarkdownFlavor) -> String {
        switch flavor {
        case .github: return s
        case .telegramV2: return MarkdownV2Escaper.escape(s)
        }
    }

    private func eu(_ url: URL, _ flavor: MarkdownFlavor) -> String {
        switch flavor {
        case .github: return url.absoluteString
        case .telegramV2:
            var out = ""
            for ch in url.absoluteString {
                if ch == ")" || ch == "\\" { out.append("\\") }
                out.append(ch)
            }
            return out
        }
    }

    private func renderCompact(_ snapshot: DailySnapshot, commitURL: URL?, flavor: MarkdownFlavor) -> String {
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        var parts: [String] = []
        if let steps = stepCount(snapshot) {
            parts.append("\(e(formatThousands(steps), flavor)) steps")
        }
        parts.append("\(snapshot.workouts.count) workout\(snapshot.workouts.count == 1 ? "" : "s")")
        if let mins = sleepMinutes(snapshot) {
            parts.append("sleep \(e(formatHoursMinutesCompact(mins), flavor))")
        }
        var line = "🫀 *Pulse Commit · \(e(dayKey, flavor))* — " + parts.joined(separator: " · ")
        if flavor == .telegramV2 { line += "\n" + telegramFreshnessLines(snapshot).joined(separator: "\n") }
        line += "\n`schema_version: \(snapshot.schemaVersion)`"
        if let url = commitURL {
            line += "\n🔗 [View on GitHub](\(eu(url, flavor)))"
        }
        return line
    }

    private func renderStandard(
        _ snapshot: DailySnapshot,
        commitURL: URL?,
        includeRawCounts: Bool,
        flavor: MarkdownFlavor
    ) -> String {
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        var lines: [String] = []
        lines.append("🫀 *Pulse Commit · \(e(dayKey, flavor))*")

        if let section = activitySection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }
        if let section = heartSection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }
        if let section = sleepSection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }
        if let section = nutritionSection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }
        if let section = bodySection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }
        if let section = workoutsSection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }
        if let section = stateOfMindSection(snapshot, flavor: flavor) { lines.append(""); lines.append(contentsOf: section) }

        if includeRawCounts {
            let raw = rawCountsSection(snapshot, flavor: flavor)
            if !raw.isEmpty {
                lines.append("")
                lines.append(contentsOf: raw)
            }
        }

        lines.append("")
        lines.append("`schema_version: \(snapshot.schemaVersion)`")
        if let url = commitURL {
            lines.append("🔗 [View on GitHub](\(eu(url, flavor)))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Sections

    private func activitySection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        var bullets: [String] = []
        if let steps = stepCount(snapshot) {
            bullets.append("• Steps: \(e(formatThousands(steps), flavor))")
        }
        if let active = doubleMetric(snapshot, category: "active_energy", key: "total") {
            bullets.append("• Active energy: \(e(formatNumber(active), flavor)) kcal")
        }
        if let rings = snapshot.summaries["activity_rings"] {
            var parts: [String] = []
            if let stand = intMetric(rings, "stand_hours") { parts.append("Stand: \(stand) h") }
            if let ex = intMetric(rings, "exercise_minutes") { parts.append("Exercise: \(ex) min") }
            if !parts.isEmpty { bullets.append("• " + parts.joined(separator: " · ")) }
        }
        guard !bullets.isEmpty else { return nil }
        return ["🏃 *Activity*"] + bullets
    }

    private func heartSection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        var bullets: [String] = []
        if let rhr = intMetric(snapshot.summaries["resting_heart_rate"], "value") {
            bullets.append("• Resting HR: \(rhr) bpm")
        }
        if let hrv = intMetric(snapshot.summaries["hrv_sdnn"], "avg") {
            bullets.append("• HRV \(e("(SDNN)", flavor)): \(hrv) ms")
        }
        if let vo2 = doubleMetric(snapshot.summaries["vo2_max"], "value") {
            bullets.append("• VO₂ max: \(e(formatNumber(vo2), flavor))")
        }
        guard !bullets.isEmpty else { return nil }
        return ["❤️ *Heart*"] + bullets
    }

    private func sleepSection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        guard let sleep = snapshot.summaries["sleep"] else { return nil }
        var bullets: [String] = []
        if let mins = intMetric(sleep, "duration_minutes") {
            bullets.append("• Duration: \(e(formatHoursMinutes(mins), flavor))")
        }
        var stageParts: [String] = []
        if let m = intMetric(sleep, "stage_deep") { stageParts.append("Deep \(e(formatHoursMinutesCompact(m), flavor))") }
        if let m = intMetric(sleep, "stage_rem") { stageParts.append("REM \(e(formatHoursMinutesCompact(m), flavor))") }
        if let m = intMetric(sleep, "stage_core") { stageParts.append("Core \(e(formatHoursMinutesCompact(m), flavor))") }
        if !stageParts.isEmpty {
            bullets.append("• " + stageParts.joined(separator: " · "))
        }
        guard !bullets.isEmpty else { return nil }
        return ["😴 *Sleep*"] + bullets
    }

    private func nutritionSection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        guard let nutrition = snapshot.summaries["nutrition"] else { return nil }
        var bullets: [String] = []
        let kcal = doubleMetric(nutrition, "energy_kcal")
        let p = doubleMetric(nutrition, "protein_g")
        let c = doubleMetric(nutrition, "carbs_g")
        let f = doubleMetric(nutrition, "fat_g")
        if let kcal {
            var line = "• \(e(formatDecimal(kcal), flavor)) kcal"
            if let p, let c, let f {
                line += " · P \(e(formatNumber(p), flavor)) / C \(e(formatNumber(c), flavor)) / F \(e(formatNumber(f), flavor))"
            }
            bullets.append(line)
        }
        if let water = doubleMetric(nutrition, "water_ml") {
            let liters = water / 1000
            bullets.append("• Water: \(e(formatNumber(liters), flavor)) L")
        }
        guard !bullets.isEmpty else { return nil }
        return ["🍽 *Nutrition*"] + bullets
    }

    private func bodySection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        guard let weight = doubleMetric(snapshot.summaries["body_mass"], "value") else { return nil }
        return ["⚖️ *Body*", "• Weight: \(e(formatNumber(weight), flavor)) kg"]
    }

    private func workoutsSection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        guard !snapshot.workouts.isEmpty else { return nil }
        var lines: [String] = ["🏋️ *Workouts \(e("(", flavor))\(snapshot.workouts.count)\(e(")", flavor))*"]
        for w in snapshot.workouts {
            for (index, line) in workoutDetailLines(w, snapshot: snapshot).enumerated() {
                lines.append(index == 0 ? "• \(e(line, flavor))" : "  \(e(line, flavor))")
            }
        }
        return lines
    }

    private func stateOfMindSection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String]? {
        guard !snapshot.stateOfMind.isEmpty else { return nil }
        let labels = snapshot.stateOfMind.flatMap { $0.labels }
        let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? []
        let joined = unique.joined(separator: ", ")
        return ["🧠 *State of Mind*: \(e(joined, flavor))"]
    }

    private func rawCountsSection(_ snapshot: DailySnapshot, flavor: MarkdownFlavor) -> [String] {
        let keys = snapshot.summaries.keys.sorted()
        guard !keys.isEmpty else { return [] }
        var lines: [String] = ["🧪 *Raw sample counts*"]
        for k in keys {
            if let count = intMetric(snapshot.summaries[k], "sample_count") {
                lines.append("• \(e(k, flavor)): \(count)")
            }
        }
        return lines.count > 1 ? lines : []
    }

    // MARK: - Helpers

    private func formatTemperature(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "en_US_POSIX")))
    }

    private func workoutDetailLines(_ workout: WorkoutDTO, snapshot: DailySnapshot) -> [String] {
        WorkoutDetailFormatter(
            timeZoneIdentifier: snapshot.timezone,
            includesDate: false,
            includesHeartRateZones: true,
            remainderStyle: .jsonAttachment
        ).lines(for: workout)
    }

    private func dateMetric(_ fragment: SummaryFragment?, _ key: String) -> Date? {
        guard case .string(let value) = fragment?.metrics[key] else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private func localTimestamp(_ date: Date, snapshot: DailySnapshot) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: snapshot.timezone) ?? .gmt
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    private func telegramFreshnessLines(_ snapshot: DailySnapshot) -> [String] {
        var lines = ["Generated: \(localTimestamp(snapshot.generatedAt, snapshot: snapshot))"]
        if let latest = snapshot.latestSampleAt {
            lines.append("Latest sample: \(localTimestamp(latest, snapshot: snapshot))")
        }
        lines.append("Time zone: \(snapshot.timezone)")
        return lines.map { e($0, .telegramV2) }
    }

    private func stepCount(_ snapshot: DailySnapshot) -> Int? {
        intMetric(snapshot.summaries["steps"], "total")
    }

    private func sleepMinutes(_ snapshot: DailySnapshot) -> Int? {
        intMetric(snapshot.summaries["sleep"], "duration_minutes")
    }

    private func intMetric(_ fragment: SummaryFragment?, _ key: String) -> Int? {
        guard let v = fragment?.metrics[key] else { return nil }
        switch v {
        case .int(let i): return i
        case .double(let d): return Int(d.rounded())
        case .string: return nil
        }
    }

    private func doubleMetric(_ snapshot: DailySnapshot, category: String, key: String) -> Double? {
        doubleMetric(snapshot.summaries[category], key)
    }

    private func doubleMetric(_ fragment: SummaryFragment?, _ key: String) -> Double? {
        guard let v = fragment?.metrics[key] else { return nil }
        switch v {
        case .int(let i): return Double(i)
        case .double(let d): return d
        case .string: return nil
        }
    }

    private func formatThousands(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.groupingSeparator = "\u{00A0}"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    private func formatDecimal(_ d: Double) -> String {
        if let integer = Int(exactly: d.rounded()), d == d.rounded() { return formatThousands(integer) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.groupingSeparator = "\u{00A0}"
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: d)) ?? String(d)
    }

    private func formatNumber(_ d: Double) -> String {
        if let integer = Int(exactly: d.rounded()), d == d.rounded() { return String(integer) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: d)) ?? String(d)
    }

    private func formatHoursMinutes(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h \(String(format: "%02d", m))m"
    }

    private func formatHoursMinutesCompact(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return "\(h)h\(String(format: "%02d", m))m"
    }

}
