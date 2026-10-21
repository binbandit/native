import Foundation
import NativeAutomation

/// Why the app couldn't do something a workflow asked of it.
enum AutomationHostError: LocalizedError {
    case appUnavailable
    case taskClosed
    case pullRequestsUnavailable
    case scriptsUnavailable
    case worktreeFailed(String)

    var errorDescription: String? {
        switch self {
        case .appUnavailable: "Native isn't ready to run workflow steps yet."
        case .taskClosed: "The step's task is no longer open."
        case .pullRequestsUnavailable: "Opening pull requests needs the GitHub feature, which isn't set up."
        case .scriptsUnavailable: "Script steps need Native's script runtime, which this build doesn't have yet."
        case .worktreeFailed(let reason): "Couldn't make a worktree for this run: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .appUnavailable: "Try again in a moment."
        case .taskClosed: "Its agent no longer has the task. Retry the step to run it in a new task."
        case .pullRequestsUnavailable:
            "Install and sign in to the GitHub CLI (gh), then retry the step, or skip it and open the pull request yourself."
        case .scriptsUnavailable: "Skip the step, or run the workflow on a newer build of Native."
        case .worktreeFailed: "Set the automation to work in the main checkout, or make the project a git repository."
        }
    }
}
