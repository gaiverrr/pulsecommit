import CryptoKit
import Foundation

struct AutomaticWorkoutConsentScope: Codable, Equatable, Sendable, Identifiable {
    static let currentDisclosureVersion = "1"
    static let currentPayloadVersion = "workout-text-v1"

    let chatID: String
    let messageThreadID: Int?
    let tokenFingerprint: String
    let disclosureVersion: String
    let payloadVersion: String

    init(
        chatID: String,
        messageThreadID: Int?,
        botToken: String,
        disclosureVersion: String = Self.currentDisclosureVersion,
        payloadVersion: String = Self.currentPayloadVersion
    ) {
        self.chatID = chatID
        self.messageThreadID = messageThreadID
        self.tokenFingerprint = Self.fingerprint(botToken)
        self.disclosureVersion = disclosureVersion
        self.payloadVersion = payloadVersion
    }

    var id: String {
        "\(chatID):\(messageThreadID.map(String.init) ?? "main"):\(tokenFingerprint):\(disclosureVersion):\(payloadVersion)"
    }

    var targetDisplayName: String {
        if let messageThreadID { return "chat \(chatID) · topic \(messageThreadID)" }
        return "chat \(chatID) · main chat"
    }

    private static func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct AutomaticWorkoutConsentRecord: Codable, Equatable, Sendable {
    let scope: AutomaticWorkoutConsentScope
    let acceptedAt: Date
    let activationID: UUID
}

final class AutomaticWorkoutConsentStore: @unchecked Sendable {
    static let storageKey = "automaticWorkoutConsent.telegram"
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.defaults = defaults
        self.clock = clock
    }

    @discardableResult
    func accept(_ scope: AutomaticWorkoutConsentScope) -> AutomaticWorkoutConsentRecord? {
        let record = AutomaticWorkoutConsentRecord(scope: scope, acceptedAt: clock(), activationID: UUID())
        guard let data = try? JSONEncoder().encode(record) else { return nil }
        lock.lock()
        defaults.set(data, forKey: Self.storageKey)
        lock.unlock()
        return record
    }

    func currentRecord(for scope: AutomaticWorkoutConsentScope) -> AutomaticWorkoutConsentRecord? {
        guard let record = record(), record.scope == scope else { return nil }
        return record
    }

    func record() -> AutomaticWorkoutConsentRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(AutomaticWorkoutConsentRecord.self, from: data)
    }

    func invalidate() {
        lock.lock()
        defaults.removeObject(forKey: Self.storageKey)
        lock.unlock()
    }
}

struct AutomaticWorkoutDisclosure: Equatable, Sendable {
    let title = "Send finished workouts automatically?"
    let target: String
    let fields = "Workout type, local start and end time with timezone, recorded duration, and available distance, energy, pace or speed, average and maximum heart rate, laps, and segments. No route, GPS, raw heart-rate samples, custom zones, full-day totals, ZIP, or JSON."
    let readers = "Chat members, bot operators, and Telegram may process each message. An external AI may process it only if you chose an AI-backed bot or chat; Pulse Commit has no AI integration."
    let retention = "Telegram and the chosen bot or chat retain messages according to their own settings."
    let timing = "After you opt in, Pulse Commit checks workouts saved to Apple Health during the last 72 hours. Delivery can be delayed while the iPhone is locked, offline, or not given background time."
    let revocation = "Turn this off to stop future attempts. Messages already sent or in flight cannot be recalled; delete remote copies in Telegram or with the bot operator."

    init(scope: AutomaticWorkoutConsentScope) { target = scope.targetDisplayName }
}
