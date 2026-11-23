import Foundation

struct WorkoutDetailFormatter: Sendable {
    enum RemainderStyle: Sendable {
        case jsonAttachment
        case omitted
    }

    let timeZoneIdentifier: String
    let includesDate: Bool
    let includesHeartRateZones: Bool
    let remainderStyle: RemainderStyle

    func lines(for workout: WorkoutDTO) -> [String] {
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .gmt
        var lines = [prettyType(workout.type)]
        lines.append("Time (\(timeZoneIdentifier)): \(local(workout.startDate, in: timeZone, includesSeconds: false))–\(local(workout.endDate, in: timeZone, includesSeconds: false))")

        var durationAndDistance = ["Duration: \(workoutDuration(workout))"]
        if let distance = positiveFinite(workout.distanceKm) {
            durationAndDistance.append("Distance: \(formatNumber(distance)) km")
        }
        lines.append(durationAndDistance.joined(separator: " · "))

        var effort: [String] = []
        if let pace = workout.averagePaceSecondsPerKilometer, let paceText = paceString(pace) {
            effort.append("Avg pace: \(paceText)/km")
        } else if let speed = positiveFinite(workout.averageSpeedKilometersPerHour) {
            effort.append("Avg speed: \(formatNumber(speed)) km/h")
        }
        if let energy = positiveFinite(workout.activeEnergyKcal) {
            effort.append("Active energy: \(formatNumber(energy)) kcal")
        }
        if !effort.isEmpty { lines.append(effort.joined(separator: " · ")) }

        var heartRate: [String] = []
        if let average = roundedPositiveInt(workout.avgHeartRate) { heartRate.append("avg \(average) bpm") }
        if let maximum = roundedPositiveInt(workout.maxHeartRate) { heartRate.append("max \(maximum) bpm") }
        if !heartRate.isEmpty { lines.append("Heart rate: " + heartRate.joined(separator: " · ")) }

        let intervals = workout.recordedIntervals ?? []
        lines.append(contentsOf: intervalLines(intervals.filter { $0.kind == .lap }, noun: "lap", timeZone: timeZone))
        lines.append(contentsOf: intervalLines(intervals.filter { $0.kind == .segment }, noun: "segment", timeZone: timeZone, distanceKm: workout.distanceKm))

        if includesHeartRateZones, let zones = workout.heartRateZones {
            lines.append("HR zones (custom, estimated)")
            for (index, seconds) in zones.secondsByZone.enumerated() {
                let range: String
                if index == 0 { range = "<\(zones.lowerBoundsBPM[0])" }
                else if index == 4 { range = ">=\(zones.lowerBoundsBPM[3])" }
                else { range = "\(zones.lowerBoundsBPM[index - 1])-\(zones.lowerBoundsBPM[index] - 1)" }
                lines.append("  Z\(index + 1) \(range) bpm: \(minutesSeconds(seconds))")
            }
            lines.append("HR coverage: \(minutesSeconds(zones.coveredSeconds)) / \(minutesSeconds(zones.activeSeconds)) active")
        }
        return lines
    }

    private func intervalLines(
        _ intervals: [WorkoutRecordedIntervalDTO],
        noun: String,
        timeZone: TimeZone,
        distanceKm: Double? = nil
    ) -> [String] {
        let valid = intervals.compactMap { interval -> (WorkoutRecordedIntervalDTO, String)? in
            guard interval.endDate > interval.startDate,
                  let duration = preciseDuration(interval.durationSeconds) else { return nil }
            return (interval, duration)
        }
        guard !valid.isEmpty else { return [] }
        let plural = noun + "s"
        let series = contiguousSeries(valid)
        let shown = series.primary
        let unit = series.otherCount > 0 ? splitUnit(distanceKm: distanceKm, count: shown.count) : nil
        var lines = ["Recorded \(plural) (\(shown.count)\(unit.map { " \($0) splits" } ?? ""), elapsed)"]
        for (index, item) in shown.prefix(4).enumerated() {
            lines.append("  \(noun.capitalized) \(index + 1): \(local(item.0.startDate, in: timeZone, includesSeconds: true))–\(local(item.0.endDate, in: timeZone, includesSeconds: true)) · \(item.1)")
        }
        let remainder = shown.count - min(shown.count, 4)
        if remainder > 0 {
            switch remainderStyle {
            case .jsonAttachment:
                lines.append("  +\(remainder) more \(remainder == 1 ? noun : plural) in JSON")
            case .omitted:
                lines.append("  \(remainder) more \(remainder == 1 ? noun : plural) omitted")
            }
        }
        if series.otherCount > 0 {
            let otherNoun = series.otherCount == 1 ? noun : plural
            let seriesText = series.otherSeries == 1 ? "an overlapping series" : "\(series.otherSeries) overlapping series"
            switch remainderStyle {
            case .jsonAttachment:
                lines.append("  +\(series.otherCount) \(otherNoun) from \(seriesText) in JSON")
            case .omitted:
                lines.append("  \(series.otherCount) \(otherNoun) from \(seriesText) omitted")
            }
        }
        return lines
    }

    private func splitUnit(distanceKm: Double?, count: Int) -> String? {
        guard let distance = positiveFinite(distanceKm), count > 0 else { return nil }
        let metersPerSplit = distance * 1_000 / Double(count)
        if abs(metersPerSplit - 1_000) <= 100 { return "km" }
        if abs(metersPerSplit - 1_609.344) <= 160 { return "mile" }
        return nil
    }

    private func contiguousSeries(
        _ items: [(WorkoutRecordedIntervalDTO, String)]
    ) -> (primary: [(WorkoutRecordedIntervalDTO, String)], otherCount: Int, otherSeries: Int) {
        let sorted = items.enumerated().sorted {
            $0.element.0.startDate == $1.element.0.startDate
                ? $0.offset < $1.offset
                : $0.element.0.startDate < $1.element.0.startDate
        }.map(\.element)
        var chains: [[(WorkoutRecordedIntervalDTO, String)]] = []
        for item in sorted {
            let candidates = chains.indices.compactMap { index -> (index: Int, gap: Double, durationDelta: Double)? in
                guard let last = chains[index].last else { return nil }
                let gap = abs(item.0.startDate.timeIntervalSince(last.0.endDate))
                guard gap <= 1 else { return nil }
                return (index, gap, abs(last.0.durationSeconds - item.0.durationSeconds))
            }
            let best = candidates.min { lhs, rhs in
                lhs.gap != rhs.gap ? lhs.gap < rhs.gap : lhs.durationDelta < rhs.durationDelta
            }
            if let index = best?.index {
                chains[index].append(item)
            } else {
                chains.append([item])
            }
        }
        let multi = chains.filter { $0.count > 1 }
        let hasParallelSeries = multi.indices.contains { i in
            multi.indices.contains { j in
                guard i < j,
                      let aStart = multi[i].first?.0.startDate, let aEnd = multi[i].last?.0.endDate,
                      let bStart = multi[j].first?.0.startDate, let bEnd = multi[j].last?.0.endDate else { return false }
                return aStart < bEnd && bStart < aEnd
            }
        }
        guard hasParallelSeries else { return (items, 0, 0) }
        let primary = chains.dropFirst().reduce(chains[0]) { best, chain in
            chain.count > best.count ? chain : best
        }
        return (primary, items.count - primary.count, chains.count - 1)
    }

    private func workoutDuration(_ workout: WorkoutDTO) -> String {
        if let duration = positiveFinite(workout.durationSeconds), let precise = preciseDuration(duration) {
            return precise
        }
        return "\(max(0, workout.durationMinutes)) min"
    }

    private func preciseDuration(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0,
              let whole = Int(exactly: seconds.rounded(.down)) else { return nil }
        let fraction = seconds - Double(whole)
        guard let roundedTenths = Int(exactly: (fraction * 10).rounded()),
              roundedTenths >= 0, roundedTenths <= 10 else { return nil }
        let carriesSecond = roundedTenths == 10
        guard !carriesSecond || whole < Int.max else { return nil }
        let normalizedWhole = whole + (carriesSecond ? 1 : 0)
        let tenth = carriesSecond ? 0 : roundedTenths
        let hours = normalizedWhole / 3_600
        let minutes = (normalizedWhole % 3_600) / 60
        let secondsComponent = normalizedWhole % 60
        let secondsText = tenth == 0 ? String(secondsComponent) : "\(secondsComponent).\(tenth)"
        if hours > 0 { return "\(hours)h \(minutes)m \(secondsText)s" }
        if minutes > 0 { return "\(minutes)m \(secondsText)s" }
        return "\(secondsText)s"
    }

    private func paceString(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds > 0,
              let rounded = Int(exactly: seconds.rounded()) else { return nil }
        return "\(rounded / 60):\(String(format: "%02d", rounded % 60))"
    }

    private func roundedPositiveInt(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return Int(exactly: value.rounded())
    }

    private func positiveFinite(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private func local(_ date: Date, in timeZone: TimeZone, includesSeconds: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        if includesDate {
            formatter.dateFormat = includesSeconds ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        } else {
            formatter.dateFormat = includesSeconds ? "HH:mm:ss" : "HH:mm"
        }
        return formatter.string(from: date)
    }

    private func minutesSeconds(_ seconds: Double) -> String {
        guard seconds.isFinite, let value = Int(exactly: max(0, seconds.rounded())) else { return "0:00" }
        return "\(value / 60):\(String(format: "%02d", value % 60))"
    }

    private func formatNumber(_ value: Double) -> String {
        if let integer = Int(exactly: value.rounded()), value == value.rounded() { return String(integer) }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func prettyType(_ type: WorkoutDTO.WorkoutType) -> String {
        switch type {
        case .outdoorRun: return "Outdoor Run"
        case .indoorRun: return "Indoor Run"
        case .outdoorCycling: return "Outdoor Cycling"
        case .indoorCycling: return "Indoor Cycling"
        case .functionalStrengthTraining: return "Functional Strength"
        case .traditionalStrengthTraining: return "Traditional Strength"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .yoga: return "Yoga"
        case .swimming: return "Swimming"
        case .other: return "Workout"
        }
    }
}
