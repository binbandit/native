import ACP
import SwiftUI

struct TaskWellToolbar<Destination: View>: View {
    let session: SessionModel
    @Bindable var tools: SessionToolsScreenModel
    let location: String
    let identity: TaskWellIdentity
    let turnChanges: TurnChangesActions?
    let detail: (TaskWellTool) -> TaskWellToolDetail
    var openSubagent: (SessionID) -> Void = { _ in }
    @ViewBuilder var destination: (TaskWellTool) -> Destination
    @State private var isLanding = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if content.isWaiting || content.status == .failed {
                if let child = session.focusTaskAttention() { openSubagent(child) }
            } else if content.showsReview {
                session.markTaskWellOutcomeReviewed(latestTurn?.id)
                turnChanges?.review()
            } else {
                tools.toggleWell()
            }
        } label: {
            TaskWellLabel(content: content)
                .opacity(tools.showsWell ? 0 : 1)
        }
        .buttonStyle(.plain)
        .dsHitTarget(DS.TaskWell.height)
        .help(help)
        .dsPopover(isPresented: $tools.showsWell, attachmentAnchor: .point(.top), arrowEdge: .bottom) {
            TaskWellToolsPanel(
                content: content, location: location, identity: identity, tools: tools, detail: detail,
                destination: destination)
        }
        .onChange(of: session.phase) { previous, phase in
            if previous == .prompting, phase == .idle {
                isLanding = true
                if tools.isOpen(.changes) { session.markTaskWellOutcomeReviewed(latestTurn?.id) }
            }
        }
        .onChange(of: tools.isOpen(.changes)) { _, isOpen in
            if isOpen, session.phase == .idle { session.markTaskWellOutcomeReviewed(latestTurn?.id) }
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
        content.attentionSince = session.taskWellAttentionSince
        if session.isStopping {
            content.status = .working
            content.verb = "Stopping"
        } else if let wait = session.wait {
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
                session: session, tools: SessionToolsScreenModel(), location: "native · main",
                identity: .init(machine: "On this Mac"), turnChanges: nil
            ) {
                _ in
                TaskWellToolDetail()
            } destination: { _ in
                EmptyView()
            }
        }
    }
}
#endif
