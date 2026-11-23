import Foundation
import HealthCore

struct SnapshotPipelineDay: Sendable {
    let snapshot: DailySnapshot
    let files: [FileEntry]
    let samplesByCategory: [String: [any SampleDTO]]
}

struct SnapshotPipeline: Sendable {
    let registry: CategoryRegistry
    let timezone: TimeZone
    let deviceName: String
    let appVersion: String
    let fileSetBuilder: SnapshotFileSetBuilder
    let clock: @Sendable () -> Date

    init(
        registry: CategoryRegistry,
        timezone: TimeZone,
        deviceName: String,
        appVersion: String,
        fileSetBuilder: SnapshotFileSetBuilder = SnapshotFileSetBuilder(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.registry = registry
        self.timezone = timezone
        self.deviceName = deviceName
        self.appVersion = appVersion
        self.fileSetBuilder = fileSetBuilder
        self.clock = clock
    }

    func run(
        from: Date,
        to: Date,
        enabledCategoryIds: Set<String>,
        verbosity: SummaryVerbosity = .standard,
        progress: RunProgressHandler? = nil
    ) async throws -> [SnapshotPipelineDay] {
        let filtered = CategoryRegistry(
            categories: registry.all.filter { enabledCategoryIds.contains($0.id) }
        )

        let normalizer = Normalizer(
            registry: filtered,
            timezone: timezone,
            deviceName: deviceName,
            appVersion: appVersion,
            clock: clock
        )
        var snapshots = try await normalizer.snapshots(from: from, to: to, progress: progress)

        // Bridge event on the success path only. If normalizer.snapshots(progress:)
        // threw, the `try await` above rethrows and we never reach this line — that
        // is correct: UI surfaces the failure via the History entry, not via a stale
        // bridge.
        await progress?(.startingSamplesFetch)

        struct FetchResult: Sendable {
            let index: Int
            let id: String
            let samples: [any SampleDTO]?
        }
        let orderedCategories = filtered.all
        let fetchResults: [FetchResult] = try await withThrowingTaskGroup(
            of: FetchResult.self
        ) { group in
            for (index, category) in orderedCategories.enumerated() {
                group.addTask {
                    do {
                        let samples = try await category.fetch(from: from, to: to)
                        return FetchResult(index: index, id: category.id, samples: samples)
                    } catch {
                        return FetchResult(index: index, id: category.id, samples: nil)
                    }
                }
            }
            var buffer: [FetchResult] = []
            buffer.reserveCapacity(orderedCategories.count)
            let totalCount = orderedCategories.count
            var completedCount = 0
            for try await result in group {
                completedCount += 1
                await progress?(.readingSamples(
                    categoryID: result.id,
                    completed: completedCount,
                    total: totalCount
                ))
                buffer.append(result)
            }
            buffer.sort { $0.index < $1.index }
            return buffer
        }

        var samplesByDay: [String: [String: [any SampleDTO]]] = [:]
        var unavailableFromSecondFetch: Set<String> = []
        for result in fetchResults {
            guard let samples = result.samples else {
                unavailableFromSecondFetch.insert(result.id)
                continue
            }
            for sample in samples {
                let key = DateBucketing.dayKey(sample.startDate, in: timezone)
                samplesByDay[key, default: [:]][result.id, default: []].append(sample)
            }
        }

        if !unavailableFromSecondFetch.isEmpty {
            let sortedUnavailable = unavailableFromSecondFetch.sorted()
            for index in snapshots.indices {
                for categoryID in sortedUnavailable {
                    snapshots[index].summaries.removeValue(forKey: categoryID)
                    if categoryID == "workouts" {
                        snapshots[index].workouts.removeAll()
                    }
                    if categoryID == "state_of_mind" {
                        snapshots[index].stateOfMind.removeAll()
                    }
                    if !snapshots[index].unavailableCategories.contains(categoryID) {
                        snapshots[index].unavailableCategories.append(categoryID)
                    }
                }
            }
        }

        var days: [SnapshotPipelineDay] = []
        for var snapshot in snapshots {
            let key = DateBucketing.dayKey(snapshot.date, in: timezone)
            var samplesByCategory = samplesByDay[key] ?? [:]
            for categoryID in snapshot.unavailableCategories {
                samplesByCategory.removeValue(forKey: categoryID)
            }
            snapshot.latestSampleAt = samplesByCategory.values
                .flatMap { $0 }
                .map { $0.endDate }
                .filter { $0 <= snapshot.generatedAt }
                .max()
            let files = try fileSetBuilder.build(
                snapshot: snapshot,
                samplesByCategory: samplesByCategory,
                verbosity: verbosity
            )
            days.append(
                SnapshotPipelineDay(
                    snapshot: snapshot,
                    files: files,
                    samplesByCategory: samplesByCategory
                )
            )
        }
        return days
    }
}
