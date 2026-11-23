import Foundation

enum HealthExportDestinationKind: String, Codable, CaseIterable, Sendable {
    case github
    case telegram
}

enum HealthExportDestinationIdentity: Codable, Equatable, Sendable {
    case github(owner: String, repo: String, branch: String, subdir: String)
    case telegram(chatID: String, messageThreadID: Int?)

    var kind: HealthExportDestinationKind {
        switch self {
        case .github: return .github
        case .telegram: return .telegram
        }
    }

    var displayName: String {
        switch self {
        case .github(let owner, let repo, let branch, let subdir):
            let base = "\(owner)/\(repo) @ \(branch)"
            return subdir.isEmpty ? base : "\(base) / \(subdir)"
        case .telegram(let chatID, let messageThreadID):
            guard let messageThreadID else { return "chat \(chatID)" }
            return "chat \(chatID) · topic \(messageThreadID)"
        }
    }
}

struct HealthExportConsentScope: Codable, Equatable, Sendable, Identifiable {
    static let currentDisclosureVersion = "1"

    let destination: HealthExportDestinationIdentity
    let enabledCategoryIds: [String]
    let disclosureVersion: String

    init(
        destination: HealthExportDestinationIdentity,
        enabledCategoryIds: Set<String>,
        disclosureVersion: String = Self.currentDisclosureVersion
    ) {
        self.destination = destination
        self.enabledCategoryIds = enabledCategoryIds.sorted()
        self.disclosureVersion = disclosureVersion
    }

    var id: String {
        "\(destination.kind.rawValue):\(destination.displayName):\(enabledCategoryIds.joined(separator: ",")):\(disclosureVersion)"
    }
}

struct HealthExportConsentRecord: Codable, Equatable, Sendable {
    let scope: HealthExportConsentScope
    let acceptedAt: Date
}

struct ConsentRequirement: Equatable, Sendable {
    let sinkID: String
    let destination: HealthExportDestinationIdentity

    func scope(for enabledCategoryIds: Set<String>) -> HealthExportConsentScope {
        HealthExportConsentScope(destination: destination, enabledCategoryIds: enabledCategoryIds)
    }
}

struct HealthExportDisclosure: Equatable, Sendable {
    let title: String
    let target: String
    let categorySummary: String
    let formats: String
    let readers: String
    let retention: String
    let deletion: String
    let version: String

    init(scope: HealthExportConsentScope) {
        target = scope.destination.displayName
        categorySummary = scope.enabledCategoryIds.joined(separator: ", ")
        version = scope.disclosureVersion
        switch scope.destination {
        case .github:
            title = "Allow Health export to GitHub?"
            formats = "summary.json, summary.md, raw samples/*.json, workout files, and route files"
            readers = "Repository collaborators and organization members with access may read the export. If the repository is public, anyone can read it."
            retention = "GitHub keeps commits according to the repository and account settings."
            deletion = "Disable this destination to stop future exports. Delete remote commits and files in GitHub; resetting Pulse Commit removes only local data."
        case .telegram:
            title = "Allow Health export to Telegram?"
            formats = "A Markdown summary and ZIP attachment containing the selected Health data"
            readers = "Chat members, bot operators, and Telegram may process the export. An AI service may also process it only if you chose an AI-backed bot or chat; Pulse Commit has no AI integration."
            retention = "Telegram and the chosen bot or chat retain messages according to their own settings."
            deletion = "Disable this destination to stop future exports. Delete remote messages in Telegram and with the bot operator; resetting Pulse Commit removes only local data."
        }
    }
}

final class HealthExportConsentStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.clock = clock
    }

    static func storageKey(for destination: HealthExportDestinationKind) -> String {
        "healthExportConsent.\(destination.rawValue)"
    }

    func accept(_ scope: HealthExportConsentScope) {
        let record = HealthExportConsentRecord(scope: scope, acceptedAt: clock())
        guard let data = try? JSONEncoder().encode(record) else { return }
        lock.withLock {
            defaults.set(data, forKey: Self.storageKey(for: scope.destination.kind))
        }
    }

    func hasCurrentConsent(for scope: HealthExportConsentScope) -> Bool {
        record(for: scope.destination.kind)?.scope == scope
    }

    func record(for destination: HealthExportDestinationKind) -> HealthExportConsentRecord? {
        lock.withLock {
            guard let data = defaults.data(forKey: Self.storageKey(for: destination)) else { return nil }
            return try? JSONDecoder().decode(HealthExportConsentRecord.self, from: data)
        }
    }

    func invalidate(_ destination: HealthExportDestinationKind) {
        lock.withLock {
            defaults.removeObject(forKey: Self.storageKey(for: destination))
        }
    }

    func reset() {
        lock.withLock {
            for destination in HealthExportDestinationKind.allCases {
                defaults.removeObject(forKey: Self.storageKey(for: destination))
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
