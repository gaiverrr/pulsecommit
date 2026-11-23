import Foundation
import HealthCore

extension GitHubAuthError {
    var userFacingMessage: String {
        localizedDescription
    }
}

extension GitHubBranchFetcherError {
    var userFacingMessage: String {
        switch self {
        case .unauthorized:
            return "Your GitHub session expired. Reconnect to continue."
        case .notFound:
            return "Repository not found."
        case .network:
            return "Couldn't reach GitHub. Check your connection."
        case .unexpected:
            return "Unexpected response from GitHub."
        }
    }
}

extension GitHubInstallationPickerError {
    var userFacingMessage: String {
        switch self {
        case .unauthorized:
            return "Your GitHub session expired. Reconnect to continue."
        case .notFound:
            return "GitHub App is not installed on the selected account."
        case .network:
            return "Couldn't reach GitHub. Check your connection."
        case .unexpected:
            return "Unexpected response from GitHub."
        }
    }
}

func gitHubUserFacingMessage(_ error: Error) -> String {
    if let authError = error as? GitHubAuthError { return authError.userFacingMessage }
    if let branchError = error as? GitHubBranchFetcherError { return branchError.userFacingMessage }
    if let pickerError = error as? GitHubInstallationPickerError { return pickerError.userFacingMessage }
    if let urlError = error as? URLError {
        return urlError.localizedDescription
    }
    return "Something went wrong. Please try again."
}
