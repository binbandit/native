import Foundation
import ProjectActions
import Terminal

/// Where an action runs: for a task, in its worktree and its terminal; for a project with no task
/// in view, in the project's folder, in the background.
struct ProjectActionTarget {
    let project: Project
    let session: SessionModel?

    var worktree: URL {
        session?.cwd ?? project.url
    }
}

/// Identifies one action's runs in one folder.
struct ProjectActionRunKey: Hashable {
    let folder: String
    let action: ProjectAction.ID

    init(_ action: ProjectAction.ID, in target: ProjectActionTarget) {
        folder = target.worktree.standardizedFileURL.path(percentEncoded: false)
        self.action = action
    }
}

/// How an action's latest run in a target is going, wherever it ran.
enum ProjectActionRunState: Equatable {
    case running(since: Date, isStopping: Bool)
    case finished(TerminalJob.Outcome)
    /// It never ran, and why.
    case couldNotStart(String)

    var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    var isStopping: Bool {
        if case .running(_, isStopping: true) = self { true } else { false }
    }

    var hasFailed: Bool {
        switch self {
        case .finished(.exited(status: let status?, _)): status != 0
        case .couldNotStart: true
        case .running, .finished: false
        }
    }
}

/// A repo action waiting on the user before it runs, since the project's repo commands aren't
/// allowed yet.
struct ProjectActionPendingRun: Identifiable {
    let id = UUID()
    let action: ProjectAction
    let target: ProjectActionTarget
}
