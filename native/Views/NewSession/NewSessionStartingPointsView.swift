import SwiftUI

/// Starting points: a short ruled ledger of real ways to begin in this project, right above the
/// composer: go back to a task, take up a pull request, run an action, or have the agent show you
/// around. Each row is a verb in its own column and the exact thing it acts on, made from what the
/// project has; with nothing to act on yet, only the ways that always work show.
struct NewSessionStartingPointsView: View {
    let context: NewSessionContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, DS.Space.lg)
            VStack(spacing: 0) {
                ForEach(points) { point in
                    SeparatorLine()
                    NewSessionLedgerRow(point: point)
                }
                SeparatorLine()
            }
            Text("Or write your own below. Type / for commands, @ to mention a file.")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .padding(.top, DS.Space.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                ProjectAvatar(name: context.projectName, icon: context.projectIcon)
                Text(context.projectName)
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            NewSessionWorkspaceLine(workspace: context.workspace, projectName: context.projectName, size: .compact)
            NewSessionChangesNote(
                count: context.checkoutChanges, workspace: context.workspace, projectName: context.projectName)
        }
    }

    /// The rows, most specific first: what's waiting on the user, then their own work, then the
    /// ways that always work.
    private var points: [NewSessionStartingPoint] {
        var points: [NewSessionStartingPoint] = []
        if let task = context.taskToContinue {
            points.append(.task(task))
        }
        if let pullRequest = context.pullRequestToTake {
            points.append(.pullRequest(pullRequest))
        }
        if let action = context.actionToRun {
            points.append(.action(action))
        }
        points.append(.ask(context.tourPrompt, draft: context.draft))
        if context.actions.isEmpty {
            points.append(.addActions(context.projectName, open: context.editActions))
        }
        return Array(points.prefix(NewSessionMetrics.ledgerLimit))
    }
}

/// One way to begin: a verb, the thing it acts on, a detail, and what happens on a click.
struct NewSessionStartingPoint: Identifiable {
    let id: String
    let verb: String
    let object: String
    var objectIsCode = false
    let detail: String?
    var detailIsCode = false
    var tone = Color.dsTextTertiary
    let glyph: String
    let hint: String
    let perform: () -> Void

    static func task(_ task: NewSessionContext.RecentTask) -> Self {
        let verb =
            switch task.status {
            case .needsInput: "Answer"
            case .needsPermission: "Approve"
            case .needsPlanReview: "Review"
            default: "Continue"
            }
        return Self(
            id: "task", verb: verb, object: task.title,
            detail: task.status.needsAttention
                ? task.status.label
                : [task.agentName, task.date.map { DSFormat.compactAge($0, now: .now) }].compactMap(\.self)
                    .joined(separator: " · "),
            tone: task.status.needsAttention ? .dsAttention : .dsTextTertiary,
            glyph: "arrow.right", hint: "Opens the task", perform: task.open)
    }

    static func pullRequest(_ pullRequest: NewSessionContext.PullRequest) -> Self {
        Self(
            id: "pull-request", verb: pullRequest.isReviewRequested ? "Review" : "Pick up",
            object: "#\(pullRequest.number) \(pullRequest.title)", detail: pullRequest.branch, detailIsCode: true,
            glyph: "arrow.down.to.line.compact", hint: "Opens it as a task in a worktree of its branch",
            perform: pullRequest.openAsTask ?? {})
    }

    static func action(_ action: NewSessionContext.Action) -> Self {
        Self(
            id: "action", verb: action.isRunning ? "Running" : "Run", object: action.name, detail: action.command,
            detailIsCode: true, glyph: action.isRunning ? "stop.fill" : "play.fill",
            hint: action.isRunning ? "Shows it in the terminal" : "Runs it in this task's terminal",
            perform: action.run)
    }

    static func ask(_ prompt: String, draft: @escaping (String) -> Void) -> Self {
        Self(
            id: "ask", verb: "Ask", object: "For a tour of the project", detail: "Drafts the prompt",
            glyph: "return", hint: "Puts a prompt in the composer for you to send", perform: { draft(prompt) })
    }

    static func addActions(_ projectName: String, open: @escaping () -> Void) -> Self {
        Self(
            id: "add-actions", verb: "Set up", object: "Actions for \(projectName)",
            detail: "Run, test or build in one click", glyph: "slider.horizontal.3",
            hint: "Opens the project's actions in Settings", perform: open)
    }
}

/// A ledger row: the verb in its column, the object, a trailing detail and the row's glyph.
private struct NewSessionLedgerRow: View {
    let point: NewSessionStartingPoint

    @State private var isHovered = false

    var body: some View {
        Button(action: point.perform) {
            HStack(spacing: DS.Space.md) {
                Text(point.verb)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextTertiary)
                    .frame(width: NewSessionMetrics.verbColumn, alignment: .leading)
                Text(point.object)
                    .font(point.objectIsCode ? .dsMono : .dsCallout)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: DS.Space.md)
                if let detail = point.detail {
                    Text(detail)
                        .font(point.detailIsCode ? .dsMonoCaption : .dsBody)
                        .foregroundStyle(point.tone)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: point.glyph)
                    .font(.dsBody)
                    .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
                    .frame(width: DS.Size.rowLeading)
            }
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: max(NewSessionMetrics.ledgerRow, DS.Size.minimumHitTarget))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background(isHovered ? Color.dsHover : .clear)
        .trackHover($isHovered)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(point.verb) \(point.object)")
        .accessibilityValue(point.detail ?? "")
        .accessibilityHint(point.hint)
        .accessibilityAddTraits(.isButton)
        .help(point.hint)
    }
}
