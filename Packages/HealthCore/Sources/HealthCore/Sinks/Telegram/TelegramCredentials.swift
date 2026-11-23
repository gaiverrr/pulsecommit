import Foundation

public struct TelegramCredentials: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let botToken: String
    public let chatID: String
    public let verbosity: SummaryVerbosity
    public let includeGitHubLink: Bool
    public let messageThreadID: Int?

    public init(
        botToken: String,
        chatID: String,
        verbosity: SummaryVerbosity = .standard,
        includeGitHubLink: Bool = true,
        messageThreadID: Int? = nil
    ) {
        self.botToken = botToken
        self.chatID = chatID
        self.verbosity = verbosity
        self.includeGitHubLink = includeGitHubLink
        self.messageThreadID = messageThreadID
    }

    public var description: String {
        "TelegramCredentials(botToken: <redacted>, chatID: \(chatID), verbosity: \(verbosity), includeGitHubLink: \(includeGitHubLink), messageThreadID: \(messageThreadID.map(String.init) ?? "nil"))"
    }

    public var debugDescription: String { description }
}
