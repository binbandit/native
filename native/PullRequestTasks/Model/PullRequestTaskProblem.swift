import ACP
import Foundation
import Git
import GitHub

/// Why opening a pull request as a task stopped, as the sheet says it: what happened, what Native
/// did about it, what the user can do, and the one action that does it.
struct PullRequestTaskProblem {
    /// Where it stopped, which decides the words.
    enum Stage {
        case lookingUp(PullRequestReference)
        case checkingOut(PullRequestDetails)
        /// The pull request is checked out; the task didn't start.
        case starting(PullRequestDetails)
        case cloning(RemoteRepository)
        case updating(PullRequestTaskCheckout.ExistingTask)
    }

    enum Action {
        /// Looks the pull request up again, rereading the environment (a gh just installed).
        case retry
        /// Opens the task as it is.
        case openTask(PullRequestTaskCheckout.ExistingTask)
        /// Back to picking the folder to clone into.
        case chooseFolder
    }

    var title: String
    var recovery: String?
    var suggestion: String?
    var details: String?
    var primary: Action = .retry
    var secondary: Action?

    init(_ error: any Error, during stage: Stage) {
        switch error {
        case let error as GitHubError: self.init(gitHub: error, stage: stage)
        case let error as GitError: self.init(git: error, stage: stage)
        default: self.init(other: error, stage: stage)
        }
    }

    /// The agent's failures, and anything unforeseen.
    private init(other error: any Error, stage: Stage) {
        title = Self.failureTitle(of: stage)
        if case .starting = stage {
            recovery = "The pull request is checked out in its worktree; trying again starts the task there."
        }
        switch error {
        case AppModel.PreparedTaskError.noAgent:
            suggestion = "Add an agent (the sheet that opened shows how), then try again."
        default:
            suggestion = error.localizedDescription.withoutTerminalEscapes
        }
    }

    private init(gitHub error: GitHubError, stage: Stage) {
        title = Self.failureTitle(of: stage)
        details = error.stderr.flatMap { $0.isEmpty ? nil : $0 }
        switch error {
        case .notInstalled:
            title = "GitHub CLI isn't installed"
            suggestion = "Native reads pull requests with your gh. Install it with “brew install gh”, then try again."
        case .notAuthenticated:
            title = "GitHub CLI isn't signed in"
            suggestion = "Run “gh auth login” in Terminal, then try again."
        case .offline, .timedOut:
            title = "Couldn't reach GitHub"
            recovery = "Nothing was changed."
            suggestion = "Check your connection, then try again."
        case .rateLimited:
            title = "GitHub's rate limit was reached"
            suggestion = "Try again in a few minutes."
        case .notFound:
            if case .lookingUp(let reference) = stage {
                title = "Couldn't find \(reference.display)"
            }
            suggestion = "It may have been deleted, or your GitHub account can't see it."
        case .failed(_, let message) where message.lowercased().contains("already exists"):
            title = "That folder isn't empty"
            recovery = "Nothing was cloned."
            suggestion = "Choose an empty folder, or one that's already a checkout of the repository."
            primary = .chooseFolder
        default:
            suggestion = [error.localizedDescription, error.recoverySuggestion].compactMap(\.self).joined(
                separator: " ")
            details = nil
            if case .cloning = stage { primary = .chooseFolder }
        }
    }

    private init(git error: GitError, stage: Stage) {
        title = Self.failureTitle(of: stage)
        if case .failed(_, _, let stderr) = error { details = stderr }
        let unchanged = "Nothing was changed."
        switch (error.failure, stage) {
        case (.networkUnavailable, _):
            title = "Couldn't reach the repository"
            recovery = unchanged
            suggestion = "Check your connection, then try again."
        case (.authenticationFailed, _):
            title = "Git couldn't sign in to fetch the pull request"
            recovery = unchanged
            suggestion =
                "Check the credentials or SSH key git uses for this repository (try “git fetch” in Terminal), then try again."
        case (.repositoryLocked, _):
            title = "Another git command is using the repository"
            recovery = unchanged
            suggestion = "Wait for it to finish, then try again."
        case (.localChangesWouldBeOverwritten, .updating(let task)):
            title = "The task has uncommitted changes the update would overwrite"
            recovery = "Native left the task as it was."
            suggestion = "Commit or discard those changes in the task, then open the pull request again to update it."
            primary = .openTask(task)
            secondary = .retry
        case (_, .updating(let task)) where Self.isNotFastForward(error):
            title = "The task and the pull request have both changed"
            recovery = "Native left the task as it was."
            suggestion =
                "The pull request was force-pushed, or the task has commits of its own. Ask the agent to merge or rebase onto “\(task.details.headRefName)”."
            primary = .openTask(task)
        default:
            suggestion = error.localizedDescription
        }
    }

    private static func failureTitle(of stage: Stage) -> String {
        switch stage {
        case .lookingUp(let reference): "Couldn't look up \(reference.display)"
        case .checkingOut(let details): "Couldn't check out #\(details.number)"
        case .starting: "Couldn't start the task"
        case .cloning(let repository): "Couldn't clone \(repository.nameWithOwner)"
        case .updating(let task): "Couldn't update “\(task.title)”"
        }
    }

    private static func isNotFastForward(_ error: GitError) -> Bool {
        guard case .failed(_, _, let stderr) = error else { return false }
        let text = stderr.lowercased()
        return text.contains("not possible to fast-forward") || text.contains("diverg")
    }
}
