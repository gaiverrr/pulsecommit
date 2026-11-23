import Foundation

actor AutomaticWorkoutAttemptFileStore: AutomaticWorkoutAttemptStoring {
    private struct Envelope: Codable {
        let version: Int
        let epoch: UUID
        var records: [AutomaticWorkoutAttemptRecord]
    }

    private let url: URL
    private let fileManager: FileManager
    private var cached: [UUID: AutomaticWorkoutAttemptRecord]?
    private var currentEpoch = UUID()
    private var storageInvalid = false

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    static func applicationSupport(fileManager: FileManager = .default) -> AutomaticWorkoutAttemptFileStore {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return AutomaticWorkoutAttemptFileStore(
            url: base.appendingPathComponent("AutomaticWorkout", isDirectory: true)
                .appendingPathComponent("attempts-v1.json"),
            fileManager: fileManager
        )
    }

    func epoch() -> UUID? {
        guard loadIfNeeded() else { return nil }
        return currentEpoch
    }

    func lookup(_ id: UUID) -> AutomaticWorkoutAttemptLookup {
        guard loadIfNeeded() else { return .unavailable }
        return cached?[id].map(AutomaticWorkoutAttemptLookup.found) ?? .missing
    }

    func latest(scopeID: String) -> AutomaticWorkoutAttemptLookup {
        guard loadIfNeeded() else { return .unavailable }
        return cached?.values.filter { $0.scopeID == scopeID }.max(by: { $0.updatedAt < $1.updatedAt })
            .map(AutomaticWorkoutAttemptLookup.found) ?? .missing
    }

    func save(_ record: AutomaticWorkoutAttemptRecord) -> Bool {
        guard loadIfNeeded(), !storageInvalid else { return false }
        cached?[record.workoutID] = record
        return persist()
    }

    func prune(olderThan cutoff: Date) -> Bool {
        guard loadIfNeeded(), !storageInvalid else { return false }
        let previous = cached?.count ?? 0
        cached = cached?.filter { $0.value.workoutEndDate >= cutoff }
        return previous == cached?.count || persist()
    }

    func reset() -> Bool {
        cached = [:]
        storageInvalid = false
        currentEpoch = UUID()
        return persist()
    }

    private func loadIfNeeded() -> Bool {
        if storageInvalid { return false }
        if cached != nil { return true }
        guard fileManager.fileExists(atPath: url.path) else {
            cached = [:]
            return true
        }
        do {
            let data = try Data(contentsOf: url)
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            var decoded: [UUID: AutomaticWorkoutAttemptRecord] = [:]
            for record in envelope.records {
                guard decoded[record.workoutID] == nil else {
                    throw CocoaError(.coderReadCorrupt)
                }
                decoded[record.workoutID] = record
            }
            currentEpoch = envelope.epoch
            cached = decoded
            return true
        } catch {
            storageInvalid = true
            return false
        }
    }

    private func persist() -> Bool {
        do {
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try mutableDirectory.setResourceValues(values)
            let envelope = Envelope(version: 1, epoch: currentEpoch, records: Array((cached ?? [:]).values))
            let data = try JSONEncoder().encode(envelope)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var fileValues = URLResourceValues()
            fileValues.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(fileValues)
            return true
        } catch {
            storageInvalid = true
            return false
        }
    }
}
