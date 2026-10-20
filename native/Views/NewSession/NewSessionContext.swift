import SwiftUI

/// What a new session's empty state shows, already looked up from the app's models
/// (`NewSessionContextBuilder`), with each starting point's action attached. The views are plain
/// over it, so they build from fixtures in previews and on iPadOS without the models.
struct NewSessionContext {
    var projectName: String
    var projectIcon: ProjectIcon
    var workspace: Workspace
    /// Uncommitted files in the project's own checkout.
    var checkoutChanges: Int
    /// The project's latest tasks with something to go back to, newest first, this one left out.
    var tasks: [RecentTask]
    /// Open pull requests in the project's repository that involve the user, reviews asked of them
    /// first.
    var pullRequests: [PullRequest]
    var actions: [Action]
    /// Puts text in the composer and focuses it, for the user to finish and send.
    var draft: (String) -> Void
    /// Opens the project's actions in Settings, to add the first one.
    var editActions: () -> Void
    /// Where the task runs, while paired hosts are on (`RemoteHosts.isEnabled`) and one is paired.
    var device: Device? = nil

    /// The device picker's rows, the device the task is on, and moving it to another.
    struct Device {
        let options: [SessionDeviceOption]
        let selection: SessionDevice
        let choose: (SessionDevice) -> Void
    }

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

        var isPlainFolder: Bool {
            if case .folder = self { true } else { false }
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
        /// Waiting on the user's review, rather than theirs or assigned to them.
        let isReviewRequested: Bool
        let branch: String?
        /// Open as Task; nil where tasks can't be opened from pull requests.
        let openAsTask: (() -> Void)?
    }

    struct Action: Identifiable {
        let id: String
        let name: String
        let command: String
        let isRunning: Bool
        /// The project's last run action, which ⇧⌘R runs again.
        let isLast: Bool
        /// Runs it in this task's terminal, or stops it while it runs.
        let run: () -> Void
    }
}

extension NewSessionContext {
    /// The task most worth going back to: one waiting on the user, else the latest.
    var taskToContinue: RecentTask? {
        tasks.first { $0.status.needsAttention } ?? tasks.first
    }

    /// The pull request most worth picking up: a review asked of the user, else the latest. Only one
    /// that can be opened as a task, since that's what picking it up does.
    var pullRequestToTake: PullRequest? {
        pullRequests.first { $0.openAsTask != nil }
    }

    /// The action most worth running: what's running, the last one run, then the first.
    var actionToRun: Action? {
        actions.first(where: \.isRunning) ?? actions.first(where: \.isLast) ?? actions.first
    }

    /// The prompt the "ask" starting point drafts: a tour of the project, for a first look.
    var tourPrompt: String {
        workspace.isPlainFolder
            ? "What's in this folder? Give me a short tour: what each part is for and where to start."
            : "Give me a short tour of this codebase: what it does, how it's organized, and where to start."
    }
}
