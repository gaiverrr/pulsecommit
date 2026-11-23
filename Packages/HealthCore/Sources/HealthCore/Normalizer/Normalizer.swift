import Foundation

public struct Normalizer: Sendable {
    public let registry: CategoryRegistry
    public let timezone: TimeZone
    public let deviceName: String
    public let appVersion: String
    public let clock: @Sendable () -> Date

    public init(
        registry: CategoryRegistry,
        timezone: TimeZone,
        deviceName: String,
        appVersion: String,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.registry = registry
        self.timezone = timezone
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.clock = clock
    }

    public func snapshots(
        from: Date,
        to: Date,
        progress: RunProgressHandler? = nil
    ) async throws -> [DailySnapshot] {
        let days = DateBucketing.days(from: from, to: to, in: timezone)
        let generatedAt = clock()
        let timezoneId = timezone.identifier

        var snapshotsByDay: [String: DailySnapshot] = [:]
        for (key, dayStart) in days {
            snapshotsByDay[key] = DailySnapshot(
                date: dayStart,
                timezone: timezoneId,
                generatedAt: generatedAt,
                deviceName: deviceName,
                appVersion: appVersion
            )
        }

        // Summary uses HealthKit's cross-source deduplicated total for cumulative
        // quantity categories (Steps, Active Energy, Distance, Activity Rings,
        // Nutrition) via HKStatisticsQuery. Raw per-source samples for
        // `samples/*.json` export are fetched separately in SnapshotPipeline.
        // Fetches run in parallel; results are reduced in the registry's declared
        // order so output (incl. unavailableCategories) stays deterministic.
        struct CategoryResult: Sendable {
            let index: Int
            let id: String
            let samples: [any SampleDTO]?
        }
        let orderedCategories = registry.all
        let results: [CategoryResult] = try await withThrowingTaskGroup(
            of: CategoryResult.self
        ) { group in
            for (index, category) in orderedCategories.enumerated() {
                group.addTask {
                    do {
                        // Cumulative categories collapse the requested range into a
                        // single whole-range DTO, so a multi-day window must be
                        // queried one day at a time or the entire total lands on
                        // the first day and days 2..N get nothing. Sample-based
                        // categories keep a single range query — fanning them out
                        // per day would multiply HealthKit round-trips for long
                        // backfills without changing the result.
                        let samples: [any SampleDTO]
                        if days.count <= 1 || !category.isCumulative {
                            samples = try await category.fetchSummarySamples(from: from, to: to)
                        } else {
                            var collected: [any SampleDTO] = []
                            for (dayIndex, day) in days.enumerated() {
                                let dayStart = max(day.dayStart, from)
                                let nextStart = dayIndex + 1 < days.count ? days[dayIndex + 1].dayStart : to
                                let dayEnd = min(nextStart, to)
                                collected += try await category.fetchSummarySamples(from: dayStart, to: dayEnd)
                            }
                            samples = collected
                        }
                        return CategoryResult(index: index, id: category.id, samples: samples)
                    } catch {
                        return CategoryResult(index: index, id: category.id, samples: nil)
                    }
                }
            }
            var buffer: [CategoryResult] = []
            buffer.reserveCapacity(orderedCategories.count)
            let totalCount = orderedCategories.count
            var completedCount = 0
            for try await result in group {
                completedCount += 1
                await progress?(.readingSummary(
                    categoryID: result.id,
                    completed: completedCount,
                    total: totalCount
                ))
                buffer.append(result)
            }
            buffer.sort { $0.index < $1.index }
            return buffer
        }

        for (offset, result) in results.enumerated() {
            let category = orderedCategories[offset]
            guard let samples = result.samples else {
                for key in snapshotsByDay.keys {
                    snapshotsByDay[key]?.unavailableCategories.append(category.id)
                }
                continue
            }
            var samplesByDay: [String: [any SampleDTO]] = [:]
            for sample in samples {
                let key = DateBucketing.dayKey(sample.startDate, in: timezone)
                samplesByDay[key, default: []].append(sample)
            }
            for (key, daySamples) in samplesByDay {
                guard var snapshot = snapshotsByDay[key] else { continue }
                let fragment = category.summarize(daySamples)
                snapshot.summaries[category.id] = fragment
                for sample in daySamples {
                    if let workoutSample = sample as? WorkoutSampleDTO {
                        snapshot.workouts.append(workoutSample.workout)
                    } else if let moodSample = sample as? StateOfMindSampleDTO {
                        snapshot.stateOfMind.append(moodSample.entry)
                    }
                }
                snapshotsByDay[key] = snapshot
            }
        }

        return days.compactMap { snapshotsByDay[$0.key] }
    }
}
