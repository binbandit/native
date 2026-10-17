import Foundation

/// Why the app couldn't do something a workflow asked of it.
enum AutomationHostError: LocalizedError {
    case appUnavailable
    case taskClosed
    case pullRequestsUnavailable

    var errorDescription: String? {
        switch self {
        case .appUnavailable: "Native isn't ready to run workflow steps yet."
        case .taskClosed: "The step's session is no longer open."
        case .pullRequestsUnavailable: "Opening pull requests needs the GitHub feature, which isn't set up."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .appUnavailable: "Try again in a moment."
        case .taskClosed: "Retry the step to run it in a new session."
        case .pullRequestsUnavailable: "Install and sign in to the GitHub CLI (gh), then retry the step, or skip it and open the pull request yourself."
        }
    }
}
