import XCTest
@testable import HealthCore

final class NormalizerTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!

    private func iso(_ string: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)!
    }

    func test_snapshots_producesOnePerDay() async throws {
        let registry = CategoryRegistry(categories: [])
        let normalizer = Normalizer(
            registry: registry,
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0",
            clock: { self.iso("2024-06-18T00:00:00Z") }
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-18T00:00:00Z")
        )
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots.map { DateBucketing.dayKey($0.date, in: utc) },
                       ["2024-06-15", "2024-06-16", "2024-06-17"])
    }

    func test_snapshots_carriesSchemaAndMetadata() async throws {
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: []),
            timezone: utc,
            deviceName: "iPhone 15",
            appVersion: "1.2.3",
            clock: { self.iso("2024-06-16T12:00:00Z") }
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-15T23:00:00Z")
        )
        let snap = try XCTUnwrap(snapshots.first)
        XCTAssertEqual(snap.schemaVersion, SchemaVersion.current)
        XCTAssertEqual(snap.timezone, utc.identifier)
        XCTAssertEqual(snap.deviceName, "iPhone 15")
        XCTAssertEqual(snap.appVersion, "1.2.3")
        XCTAssertEqual(snap.generatedAt, iso("2024-06-16T12:00:00Z"))
    }

    func test_snapshots_bucketsSamplesByDayAndSummarizes() async throws {
        let s1 = SampleFixtures.quantity(categoryID: "steps", start: "2024-06-15T08:00:00Z", value: 100)
        let s2 = SampleFixtures.quantity(categoryID: "steps", start: "2024-06-15T20:00:00Z", value: 250)
        let s3 = SampleFixtures.quantity(categoryID: "steps", start: "2024-06-16T09:00:00Z", value: 400)

        let stub = FixtureCategory(
            id: "steps",
            displayName: "Steps",
            samples: [s1, s2, s3],
            summarizer: { samples in
                let total = samples.compactMap { ($0 as? QuantitySampleDTO)?.value }.reduce(0, +)
                return SummaryFragment(metrics: ["total": .int(Int(total))], unit: "count")
            }
        )

        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [stub]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-16T23:59:59Z")
        )

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].summaries["steps"]?.metrics["total"], .int(350))
        XCTAssertEqual(snapshots[0].summaries["steps"]?.unit, "count")
        XCTAssertEqual(snapshots[1].summaries["steps"]?.metrics["total"], .int(400))
    }

    func test_snapshots_foldsWorkoutSampleIntoWorkouts() async throws {
        let workout = WorkoutDTO(
            id: "w1",
            type: .outdoorRun,
            startDate: iso("2024-06-15T08:00:00Z"),
            endDate: iso("2024-06-15T08:30:00Z"),
            durationMinutes: 30,
            distanceKm: 5.0,
            activeEnergyKcal: 300,
            avgHeartRate: 150,
            maxHeartRate: 170,
            route: []
        )
        let workoutSample = WorkoutSampleDTO(
            categoryID: "workouts",
            sourceName: "Apple Watch",
            sourceBundleID: "com.apple.health",
            workout: workout
        )
        let stub = FixtureCategory(
            id: "workouts",
            displayName: "Workouts",
            samples: [workoutSample],
            summarizer: { samples in
                SummaryFragment(metrics: ["count": .int(samples.count)])
            }
        )
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [stub]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-15T23:59:59Z")
        )
        XCTAssertEqual(snapshots.first?.workouts, [workout])
        XCTAssertEqual(snapshots.first?.summaries["workouts"]?.metrics["count"], .int(1))
    }

    /// Mirrors the production cumulative adapters (`fetchCumulativeTotal`):
    /// `fetchSummarySamples` returns ONE DTO spanning the whole requested
    /// range, carrying the deduplicated total for exactly that range.
    private struct CumulativeFixtureCategory: HealthCategory {
        let id: String
        let displayName = "Cumulative Stub"
        let isCumulative = true
        let dailyTotals: [String: Double]

        func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { [] }

        func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] {
            let utc = TimeZone(identifier: "UTC")!
            let total = DateBucketing.days(from: from, to: to, in: utc)
                .compactMap { dailyTotals[$0.key] }
                .reduce(0, +)
            guard total > 0 else { return [] }
            return [QuantitySampleDTO(
                categoryID: id,
                startDate: from,
                endDate: to,
                value: total,
                unit: "count",
                sourceName: "HealthKit (deduplicated)",
                sourceBundleID: "com.apple.health"
            )]
        }

        func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
            let total = samples.compactMap { ($0 as? QuantitySampleDTO)?.value }.reduce(0, +)
            return SummaryFragment(metrics: ["total": .int(Int(total))], unit: "count")
        }
    }

    private final class FetchCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var _count = 0
        func increment() { lock.lock(); _count += 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    }

    private struct CountingCategory: HealthCategory {
        let id = "counting"
        let displayName = "Counting"
        let counter: FetchCounter
        func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
            counter.increment()
            return []
        }
        func summarize(_ samples: [any SampleDTO]) -> SummaryFragment { SummaryFragment() }
    }

    func test_snapshots_multiDayWindow_fetchesNonCumulativeCategoriesInOneQuery() async throws {
        let counter = FetchCounter()
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [CountingCategory(counter: counter)]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        _ = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-18T00:00:00Z")
        )
        XCTAssertEqual(
            counter.count, 1,
            "Sample-based categories return per-sample data for any range in a single query; fanning them out per day multiplies HealthKit round-trips (a 365-day backfill would issue thousands)"
        )
    }

    func test_snapshots_multiDayWindow_attributesCumulativeTotalsToEachDay() async throws {
        let stub = CumulativeFixtureCategory(id: "steps", dailyTotals: [
            "2024-06-15": 100,
            "2024-06-16": 200,
            "2024-06-17": 300,
        ])
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [stub]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-18T00:00:00Z")
        )
        XCTAssertEqual(snapshots.count, 3)
        XCTAssertEqual(snapshots[0].summaries["steps"]?.metrics["total"], .int(100))
        XCTAssertEqual(snapshots[1].summaries["steps"]?.metrics["total"], .int(200))
        XCTAssertEqual(snapshots[2].summaries["steps"]?.metrics["total"], .int(300))
    }

    func test_snapshots_foldsStateOfMindSampleIntoStateOfMind() async throws {
        let entry = StateOfMindEntryDTO(
            time: iso("2024-06-15T10:00:00Z"),
            valence: 0.5,
            labels: ["happy"]
        )
        let moodSample = StateOfMindSampleDTO(
            categoryID: "state_of_mind",
            sourceName: "Health",
            sourceBundleID: "com.apple.health",
            entry: entry
        )
        let stub = FixtureCategory(
            id: "state_of_mind",
            displayName: "State of Mind",
            samples: [moodSample],
            summarizer: { samples in
                SummaryFragment(metrics: ["count": .int(samples.count)])
            }
        )
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [stub]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-15T23:59:59Z")
        )
        XCTAssertEqual(snapshots.first?.stateOfMind, [entry])
        XCTAssertEqual(snapshots.first?.summaries["state_of_mind"]?.metrics["count"], .int(1))
    }

    func test_snapshots_recordsUnavailableCategoryOnFetchError() async throws {
        struct FailingCategory: HealthCategory {
            let id = "failing"
            let displayName = "Failing"
            func fetch(from: Date, to: Date) async throws -> [any SampleDTO] {
                throw NSError(domain: "Test", code: 1)
            }
            func summarize(_ samples: [any SampleDTO]) -> SummaryFragment { SummaryFragment() }
        }
        let working = FixtureCategory(
            id: "steps",
            samples: [SampleFixtures.quantity(categoryID: "steps", start: "2024-06-15T08:00:00Z", value: 100)],
            summarizer: { _ in SummaryFragment(metrics: ["total": .int(100)]) }
        )
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [FailingCategory(), working]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-15T23:59:59Z")
        )
        XCTAssertEqual(snapshots.first?.unavailableCategories, ["failing"])
        XCTAssertEqual(snapshots.first?.summaries["steps"]?.metrics["total"], .int(100))
    }

    func test_snapshots_fetchesCategoriesConcurrently() async throws {
        let delayMs: UInt64 = 200
        let delayNanos = delayMs * 1_000_000
        let categories: [any HealthCategory] = (0..<8).map { idx in
            FixtureCategory(
                id: "cat\(idx)",
                samples: [SampleFixtures.quantity(categoryID: "cat\(idx)", start: "2024-06-15T08:00:00Z", value: 1)],
                summarizer: { _ in SummaryFragment(metrics: ["v": .int(1)]) },
                fetchDelayNanoseconds: delayNanos
            )
        }
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: categories),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let start = Date()
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-15T23:59:59Z")
        )
        let elapsed = Date().timeIntervalSince(start)
        // Sequential would be ~8 * 0.2 = 1.6s. Parallel should be well under 1.0s.
        XCTAssertLessThan(elapsed, 1.0, "expected parallel fetch, took \(elapsed)s")
        XCTAssertEqual(snapshots.first?.summaries.count, 8)
    }

    func test_snapshots_omitsSummaryWhenNoSamplesForDay() async throws {
        let s1 = SampleFixtures.quantity(categoryID: "steps", start: "2024-06-15T08:00:00Z", value: 100)
        let stub = FixtureCategory(
            id: "steps",
            samples: [s1],
            summarizer: { _ in SummaryFragment(metrics: ["total": .int(100)]) }
        )
        let normalizer = Normalizer(
            registry: CategoryRegistry(categories: [stub]),
            timezone: utc,
            deviceName: "iPhone",
            appVersion: "1.0"
        )
        let snapshots = try await normalizer.snapshots(
            from: iso("2024-06-15T00:00:00Z"),
            to: iso("2024-06-16T23:59:59Z")
        )
        XCTAssertEqual(snapshots[0].summaries["steps"]?.metrics["total"], .int(100))
        XCTAssertNil(snapshots[1].summaries["steps"])
    }

    func test_snapshots_emitsReadingSummaryPerCategoryCompletion() async throws {
        // Fixture registry with 3 categories — Normalizer's TaskGroup will fire one
        // .readingSummary event per category as it completes. Order may vary (parallel)
        // but final event must be (_, 3, 3).
        let fixture = NormalizerFixture.makeWithCategoryCount(3)
        let normalizer = Normalizer(
            registry: fixture.registry,
            timezone: TimeZone(identifier: "UTC")!,
            deviceName: "iPhone-Test",
            appVersion: "1.0.0",
            clock: { fixture.fixedDate }
        )

        let captured = ActorIsolatedEvents()
        let handler: RunProgressHandler = { event in
            await captured.append(event)
        }

        _ = try await normalizer.snapshots(
            from: fixture.fixedDate.addingTimeInterval(-86400),
            to: fixture.fixedDate,
            progress: handler
        )

        let events = await captured.events
        XCTAssertEqual(events.count, 3, "expected one .readingSummary per category")
        for event in events {
            guard case let .readingSummary(categoryID: _, completed: _, total: total) = event else {
                return XCTFail("non-.readingSummary event: \(event)")
            }
            XCTAssertEqual(total, 3)
        }
        let lastEvent = try XCTUnwrap(events.last, "events must not be empty")
        guard case let .readingSummary(categoryID: _, completed: lastCompleted, total: _) = lastEvent else {
            return XCTFail("last event should be .readingSummary, got \(lastEvent)")
        }
        XCTAssertEqual(lastCompleted, 3, "final event must have completed == total")
    }
}

// Tiny test fixture: N categories that return zero summary samples each.
private struct NormalizerFixture {
    let registry: CategoryRegistry
    let fixedDate: Date

    static func makeWithCategoryCount(_ n: Int) -> NormalizerFixture {
        let cats: [any HealthCategory] = (0..<n).map { StubCategory(id: "cat\($0)") }
        return NormalizerFixture(
            registry: CategoryRegistry(categories: cats),
            fixedDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}

private struct StubCategory: HealthCategory {
    let id: String
    var displayName: String { id }
    func fetch(from: Date, to: Date) async throws -> [any SampleDTO] { [] }
    func fetchSummarySamples(from: Date, to: Date) async throws -> [any SampleDTO] { [] }
    func summarize(_ samples: [any SampleDTO]) -> SummaryFragment {
        SummaryFragment(metrics: [:], unit: "count")
    }
}

actor ActorIsolatedEvents {
    private(set) var events: [RunProgress] = []
    func append(_ event: RunProgress) { events.append(event) }
}
