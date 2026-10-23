import ACP
import SwiftUI

struct TaskWellToolbar<Dev: View>: View {
    let session: SessionModel
    @Bindable var tools: SessionToolsScreenModel
    let location: String
    let turnChanges: TurnChangesActions?
    let detail: (TaskWellTool) -> String
    @ViewBuilder var dev: () -> Dev
    @State private var isLanding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if content.isWaiting || content.status == .failed {
                session.focusTaskAttention()
            } else if content.showsReview {
                session.markTaskWellOutcomeReviewed(latestTurn?.id)
                turnChanges?.review()
            } else {
                tools.toggleWell()
            }
        } label: {
            TaskWellLabel(content: content)
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.TaskWell.height)
        .help(help)
        .popover(isPresented: $tools.showsWell, arrowEdge: .bottom) {
            TaskWellToolsPanel(content: content, location: location, tools: tools, detail: detail, dev: dev)
        }
        .onChange(of: session.phase) { previous, phase in
            if previous == .prompting, phase == .idle { isLanding = true }
        }
        .onChange(of: tools.isOpen(.changes)) { _, isOpen in
            if isOpen { session.markTaskWellOutcomeReviewed(latestTurn?.id) }
        }
        .task(id: isLanding) {
            guard isLanding else { return }
            try? await Task.sleep(for: DS.TaskWell.seenDelay)
            guard !Task.isCancelled else { return }
            isLanding = false
        }
        .animation(reduceMotion ? nil : .dsStandard, value: content)
    }

    private var latestTurn: TranscriptTurn? { session.state.turns.last(where: { !$0.isLateOutput }) }

    private var help: String {
        let action =
            content.isWaiting
            ? "Show the request. "
            : content.status == .failed
                ? "Show the failure. " : content.showsReview ? "Review this turn's changes. " : ""
        return action + CommandRegistry.shared.help("Task tools", for: .taskWellToggle)
    }

    private var content: TaskWellContent {
        var content = TaskWellContent(status: session.taskStatus, agent: session.agentName)
        if let wait = session.wait {
            content.verb = "Waiting on you"
            // Preserve the ask verbatim. Tool kind is not enough to tell push from overwrite.
            content.object =
                switch wait {
                case .permission(let reason), .input(let reason), .planReview(let reason): reason
                }
        } else if session.needsApproval {
            content.verb = "Waiting on you"
            content.object = "A subagent needs your approval"
        } else if session.isRetryScheduled {
            content.verb = "Reconnecting"
        } else if session.phase == .prompting {
            let activity = session.taskActivity
            content.verb = activity.verb
            content.object = activity.object
            content.progress = activity.progress
        } else if content.status == .starting {
            content.verb = "Starting"
        } else if content.status == .failed {
            content.verb = "Turn failed"
            content.object = "See the conversation"
        } else if content.status == .cancelled {
            content.verb = "Stopped"
        } else {
            content.status = isLanding ? .done : .idle
            if let turn = latestTurn, turn.id != session.reviewedTaskWellTurnID, let turnChanges {
                var summary = session.state.summary(of: turn)
                if let detected = turnChanges.latestTurnChanges, detected.startedAt == turn.startedAt {
                    summary.changedFiles = detected.files
                }
                if !summary.changedFiles.isEmpty {
                    content.outcome = summary
                    content.showsReview = !tools.isOpen(.changes)
                }
            }
        }
        return content
    }
}

#if DEBUG
#Preview("Well - Resting toolbar") {
    let app = AppModel.preview()
    return DSPreviewPair {
        if let session = SessionModel.preview(in: app) {
            TaskWellToolbar(
                session: session, tools: SessionToolsScreenModel(), location: "native · main", turnChanges: nil
            ) {
                _ in
                ""
            } dev: {
                EmptyView()
            }
        }
    }
}
#endif
