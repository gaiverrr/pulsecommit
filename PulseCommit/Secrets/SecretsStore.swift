import Foundation

/// All implementations MUST move SecItem* / lock-protected work off the main
/// actor. `KeychainSecretsStore` is an actor; `InMemorySecretsStore` is an
/// actor; callers that need synchronous reads should `await` inside a Task.
protocol SecretsStore: Sendable {
    func get(_ key: String) async throws -> String?
    func set(_ value: String?, for key: String) async throws
}
