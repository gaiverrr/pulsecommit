import Foundation

enum ChatIdValidation: Equatable {
    case invalid
    case warning
    case valid

    var isSaveEnabled: Bool {
        switch self {
        case .invalid: return false
        case .warning, .valid: return true
        }
    }
}

enum ChatIdValidator {
    private static let chatIDPattern = #"^-?\d+$"#
    private static let supergroupMissingMinusPattern = #"^100\d{9,}$"#

    static func validate(_ raw: String) -> ChatIdValidation {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: chatIDPattern, options: .regularExpression) != nil else {
            return .invalid
        }
        if trimmed.range(of: supergroupMissingMinusPattern, options: .regularExpression) != nil {
            return .warning
        }
        return .valid
    }
}
