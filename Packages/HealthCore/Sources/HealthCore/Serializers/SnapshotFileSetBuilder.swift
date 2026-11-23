import Foundation

public struct SnapshotFileSetBuilder: Sendable {
    private let summaryJSON: SummaryJSONSerializer
    private let samplesJSON: SamplesJSONSerializer
    private let workoutFiles: WorkoutFilesSerializer
    private let summaryMarkdown: SummaryMarkdownSerializer

    public init(
        summaryJSON: SummaryJSONSerializer = SummaryJSONSerializer(),
        samplesJSON: SamplesJSONSerializer = SamplesJSONSerializer(),
        workoutFiles: WorkoutFilesSerializer = WorkoutFilesSerializer(),
        summaryMarkdown: SummaryMarkdownSerializer = SummaryMarkdownSerializer()
    ) {
        self.summaryJSON = summaryJSON
        self.samplesJSON = samplesJSON
        self.workoutFiles = workoutFiles
        self.summaryMarkdown = summaryMarkdown
    }

    public func build(
        snapshot: DailySnapshot,
        samplesByCategory: [String: [any SampleDTO]] = [:],
        verbosity: SummaryVerbosity = .standard
    ) throws -> [FileEntry] {
        let dayKey = SummaryJSONSerializer.dayKey(for: snapshot.date, timezone: snapshot.timezone)
        var entries: [FileEntry] = []

        let summaryData = try summaryJSON.serialize(snapshot)
        entries.append(FileEntry(path: "summary.json", data: summaryData))

        let markdown = summaryMarkdown.serialize(snapshot, verbosity: verbosity)
        entries.append(FileEntry(path: "summary.md", data: Data(markdown.utf8)))

        entries.append(contentsOf: try samplesJSON.serialize(samplesByCategory: samplesByCategory))
        entries.append(contentsOf: try workoutFiles.serialize(workouts: snapshot.workouts))

        return entries.map { FileEntry(path: "\(dayKey)/\($0.path)", data: $0.data) }
    }
}
