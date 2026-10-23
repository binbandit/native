import Foundation
import TaskScripts

// How Native names each event, its scripts and their sources, in Settings and in the task's log.
// Plain strings, so they're nonisolated: a script's name goes into its output from the runner's queue.
extension TaskScriptEvent {
    var plainlyCopy: SettingsPlainlyCopy {
        switch self {
        case .beforeWorktree, .afterWorktree:
            .init(title: title, description: summary)
        case .setup:
            .init(
                title: "After the worktree is made", description: "Install dependencies here. The agent waits for it.")
        case .taskStarted: .init(title: "When a task starts")
        case .turnFinished: .init(title: "After each turn")
        case .teardown:
            .init(
                title: "Before the worktree is removed",
                description: "Stop servers here. A failure never blocks removal.")
        case .taskDeleted: .init(title: "After a task is deleted")
        }
    }

    nonisolated var title: String {
        switch self {
        case .beforeWorktree: "Before creating a worktree"
        case .afterWorktree: "After creating a worktree"
        case .setup: "Setup"
        case .taskStarted: "Task started"
        case .turnFinished: "Turn finished"
        case .teardown: "Teardown"
        case .taskDeleted: "Task deleted"
        }
    }

    /// When it runs, for Settings.
    nonisolated var summary: String {
        switch self {
        case .beforeWorktree:
            "Runs in the project folder before fetching the base branch and creating the task's worktree. A failure leaves the task ready to retry."
        case .afterWorktree:
            "Runs in the new task's worktree in the background. Its output and Retry are in the task's terminal; your first message does not wait."
        case .setup:
            "When Native makes a task's worktree, after copying its env files. The agent waits for it, so install dependencies or start services here."
        case .taskStarted: "When a task starts, in its worktree or the project's folder."
        case .turnFinished: "Each time the agent finishes a turn."
        case .teardown:
            "Before Native removes a task's worktree, when the task is archived or deleted. Stop servers and clean caches here; a failure never stops the removal."
        case .taskDeleted: "Once a task is deleted for good, after the undo window."
        }
    }

    nonisolated var systemImage: String {
        switch self {
        case .beforeWorktree: "arrow.down.to.line"
        case .afterWorktree: "terminal"
        case .setup: "hammer"
        case .taskStarted: "play"
        case .turnFinished: "checkmark.bubble"
        case .teardown: "wind"
        case .taskDeleted: "trash"
        }
    }
}

extension TaskScript.Source {
    /// Where the script comes from, as a badge says it.
    nonisolated var label: String {
        switch self {
        case .global: "Global"
        case .project: "This project"
        case .repository: "From the repo"
        }
    }
}

extension TaskScript {
    /// "The repository's setup script (.native/setup.sh)", as a sentence's subject.
    nonisolated var name: String {
        switch source {
        case .global: "The global \(event.title.lowercased()) script"
        case .project: "The project's \(event.title.lowercased()) script"
        case .repository: "The repository's \(event.title.lowercased()) script (\(event.repositoryPath))"
        }
    }
}

extension TaskScriptResult.Outcome {
    /// What happened, in a short phrase: "failed with exit code 1".
    nonisolated var phrase: String {
        switch self {
        case .succeeded: "finished"
        case .failed(let exitCode): "failed with exit code \(exitCode)"
        case .timedOut(let after): "was stopped after \(TaskScriptTimeouts.title(after)), its time limit"
        case .cancelled: "was stopped"
        case .couldNotStart: "couldn't start"
        }
    }
}

/// The time limits Settings offers for an event's scripts.
nonisolated enum TaskScriptTimeouts {
    static let choices: [Duration] = [30, 60, 120, 300, 600, 900, 1800, 3600].map { .seconds($0) }

    /// "1 minute", "10 minutes".
    static func title(_ timeout: Duration) -> String {
        timeout.formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}

/// The environment variables every script gets, for Settings' reference.
enum TaskScriptVariables {
    static let all: [(name: String, meaning: String)] = [
        (
            "NATIVE_EVENT",
            "before-worktree, after-worktree, setup, task-started, turn-finished, teardown or task-deleted"
        ),
        ("NATIVE_PROJECT_PATH", "The project's main checkout"),
        ("NATIVE_WORKTREE_PATH", "The task's folder, where the script runs"),
        ("NATIVE_BRANCH", "The task's branch"),
        ("NATIVE_BASE_BRANCH", "The branch the worktree was made from (setup)"),
        ("NATIVE_TASK_ID", "The agent's id for the task (empty during setup)"),
        ("NATIVE_TASK_TITLE", "The task's title (empty during setup)"),
        ("NATIVE_AGENT", "The agent's id, such as codex or claude-code"),
    ]
}
