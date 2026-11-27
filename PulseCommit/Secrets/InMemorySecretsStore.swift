import Foundation

actor InMemorySecretsStore: SecretsStore {
    private var storage: [String: String]

    init(_ storage: [String: String] = [:]) {
        self.storage = storage
    }

    func get(_ key: String) throws -> String? {
        storage[key]
    }

    func set(_ value: String?, for key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }
}
