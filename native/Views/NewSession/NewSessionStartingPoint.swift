import SwiftUI

/// One way to begin a new session: a verb, the exact thing it acts on, a detail, the glyph for what
/// a click does, and the click itself.
struct NewSessionStartingPoint: Identifiable {
    let id: String
    let verb: String
    let object: String
    let detail: String?
    var detailIsCode = false
    /// The detail's color: tertiary, or the attention color while a task waits on the user.
    var tone = Color.dsTextTertiary
    let glyph: String
    /// What a click does, for VoiceOver and the tooltip.
    let hint: String
    let perform: () -> Void
}

extension NewSessionStartingPoint {
    /// The rows for a project, most specific first: a task (waiting on the user, or the latest), a
    /// pull request to take up, an action to run, then the ways that always work.
    static func points(for context: NewSessionContext) -> [Self] {
        var points: [Self] = []
        if let task = context.taskToContinue {
            points.append(.task(task))
        }
        if let pullRequest = context.pullRequestToTake {
            points.append(.pullRequest(pullRequest))
        }
        if let action = context.actionToRun {
            points.append(.action(action))
        }
        points.append(.ask(context.tourPrompt, isFolder: context.workspace.isPlainFolder, draft: context.draft))
        if context.actions.isEmpty {
            points.append(.addActions(context.projectName, open: context.editActions))
        }
        return points
    }

    static func task(_ task: NewSessionContext.RecentTask) -> Self {
        let verb =
            switch task.status {
            case .needsInput: "Answer"
            case .needsPermission: "Approve"
            case .needsPlanReview: "Review"
            default: "Continue"
            }
        let detail =
            task.status.needsAttention
            ? task.status.label
            : [task.agentName, task.date.map { DSFormat.compactAge($0, now: .now) }].compactMap(\.self)
                .joined(separator: " · ")
        return Self(
            id: "task", verb: verb, object: task.title, detail: detail,
            tone: task.status.needsAttention ? .dsAttention : .dsTextTertiary, glyph: "arrow.right",
            hint: "Opens the task", perform: task.open)
    }

    static func pullRequest(_ pullRequest: NewSessionContext.PullRequest) -> Self {
        Self(
            id: "pull-request", verb: pullRequest.isReviewRequested ? "Review" : "Pick up",
            object: "#\(pullRequest.number) \(pullRequest.title)", detail: pullRequest.branch, detailIsCode: true,
            glyph: "arrow.down.to.line.compact", hint: "Opens it as a task, in a worktree of its branch",
            perform: pullRequest.openAsTask ?? {})
    }

    static func action(_ action: NewSessionContext.Action) -> Self {
        Self(
            id: "action", verb: action.isRunning ? "Stop" : "Run", object: action.name, detail: action.command,
            detailIsCode: true, glyph: action.isRunning ? "stop.fill" : "play.fill",
            hint: action.isRunning ? "Stops it" : "Runs it in this task's terminal", perform: action.run)
    }

    static func ask(_ prompt: String, isFolder: Bool, draft: @escaping (String) -> Void) -> Self {
        Self(
            id: "ask", verb: "Ask", object: isFolder ? "What's in this folder" : "For a tour of the codebase",
            detail: "Drafts the prompt", glyph: "return", hint: "Puts a prompt in the composer for you to send",
            perform: { draft(prompt) })
    }

    static func addActions(_ projectName: String, open: @escaping () -> Void) -> Self {
        Self(
            id: "add-actions", verb: "Set up", object: "Actions for \(projectName)",
            detail: "Run, test or build in one click", glyph: "slider.horizontal.3",
            hint: "Opens the project's actions in Settings", perform: open)
    }
}
