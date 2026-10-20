import SwiftUI

/// What a new session's empty state shows, already looked up from the app's models
/// (`NewSessionContextBuilder`), with each row's action attached. The designs are plain views over
/// it, so they build from fixtures in previews and on iPadOS without the models.
struct NewSessionContext {
    var projectName: String
    var projectIcon: ProjectIcon
    var workspace: Workspace
    /// Uncommitted files in the project's own checkout.
    var checkoutChanges: Int
    /// The project's latest tasks, this one left out.
    var tasks: [RecentTask]
    /// Open pull requests in the project's repository that involve the user.
    var pullRequests: [PullRequest]
    /// The repository on GitHub, `owner/name`, once its remotes are read.
    var repository: String?
    var actions: [Action]
    var setup: Setup?
    var keys: Keys
    /// Puts text in the composer and focuses it, for the user to finish and send.
    var draft: (String) -> Void
    /// Opens the project's actions in Settings, to add the first one.
    var editActions: () -> Void

    /// Where the task works.
    enum Workspace: Equatable {
        /// Its own worktree, on a new branch from `base`.
        case worktree(branch: String, base: String?)
        /// The project's own checkout, on `branch`.
        case checkout(branch: String?)
        /// A folder that isn't a git repository.
        case folder(path: String)
        /// Git hasn't answered yet.
        case unknown(path: String)

        var branch: String? {
            switch self {
            case .worktree(let branch, _): branch
            case .checkout(let branch): branch
            case .folder, .unknown: nil
            }
        }

        /// Whether the task has a checkout of its own, so the project's changes aren't in it.
        var isIsolated: Bool {
            if case .worktree = self { true } else { false }
        }
    }

    struct RecentTask: Identifiable {
        let id: String
        let title: String
        let agentName: String
        let status: TaskStatus
        let date: Date?
        let open: () -> Void
    }

    struct PullRequest: Identifiable {
        let id: URL
        let number: Int
        let title: String
        let isDraft: Bool
        /// Waiting on the user's review, rather than theirs or assigned to them.
        let isReviewRequested: Bool
        let branch: String?
        let updatedAt: Date
        /// Open as Task; nil where tasks can't be opened from pull requests.
        let openAsTask: (() -> Void)?
    }

    struct Action: Identifiable {
        let id: String
        let name: String
        let command: String
        let icon: String
        let isRunning: Bool
        /// The project's last run action, which ⇧⌘R runs again.
        let isLast: Bool
        let run: () -> Void
    }

    enum Setup: Equatable {
        case waiting
        case running(since: Date)
        case done(seconds: TimeInterval?)
        case failed(String)
    }

    /// Shortcut labels as the user has them, for hints.
    struct Keys {
        var palette: String?
        var runLast: String?
        var terminal: String?
    }
}

extension NewSessionContext {
    /// The task most worth going back to: one waiting on the user, else the latest.
    var taskToContinue: RecentTask? {
        tasks.first { $0.status.needsAttention } ?? tasks.first
    }

    /// The action most worth running: what's running, the last one run, then the first.
    var actionToRun: Action? {
        actions.first(where: \.isRunning) ?? actions.first(where: \.isLast) ?? actions.first
    }

    /// The pull request most worth picking up: a review asked of the user, else the latest.
    var pullRequestToTake: PullRequest? {
        pullRequests.first(where: \.isReviewRequested) ?? pullRequests.first
    }

    /// The prompt the "ask" starting point drafts: a tour of the project, for a first look.
    var tourPrompt: String {
        switch workspace {
        case .folder:
            "What's in this folder? Give me a short tour: what each part is for and where to start."
        case .worktree, .checkout, .unknown:
            "Give me a short tour of this codebase: what it does, how it's organized, and where to start."
        }
    }
}
