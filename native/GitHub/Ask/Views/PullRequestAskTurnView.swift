import ACP
import GitHub
import SwiftUI

/// One question and its answer: the question, what the context carried (on the first one), the
/// agent's tool work folded to one line, any request waiting on the user, the answer, and how it
/// ended when it didn't end well.
struct PullRequestAskTurnView: View {
    let conversation: PullRequestAskConversation
    let turn: PullRequestAskTurn
    let isLatest: Bool

    @State private var showsActivity = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if let question = turn.question {
                PullRequestAskQuestionBubble(text: question)
            }
            if let carried = turn.carried, carried != .followUp, let inclusion = conversation.record?.inclusion {
                PullRequestAskContextNote(inclusion: inclusion, isRefresh: carried == .refreshed)
            }
            ForEach(turn.commentary.indices, id: \.self) { index in
                Text(verbatim: turn.commentary[index])
                    .font(.dsCallout)
                    .foregroundStyle(.dsTextSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !turn.activity.isEmpty {
                TurnActivityFold(summary: turn.summary, isUnfolded: showsActivity) {
                    withAnimation(.reveal) { showsActivity.toggle() }
                }
                if showsActivity {
                    ForEach(turn.activity) { row in
                        activityRow(row)
                    }
                    .transition(RevealTransition())
                }
            }
            ForEach(turn.requests, id: \.id) { call in
                ToolCallView(call: call) { option in choose(option, for: call) }
                    // Only the oldest request answers ⌘Y, as in the transcript.
                    .environment(\.permissionShortcutsEnabled, isLatest && call.id == turn.requests.first?.id)
            }
            if !turn.answer.isEmpty {
                PullRequestAskAnswer(text: turn.answer, isFinished: !turn.isRunning) { conversation.draftComment($0) }
            }
            if turn.isRunning, let current = turn.current {
                PullRequestAskStatusLine(text: current)
            }
            ForEach(turn.notices, id: \.id) { notice in
                NoticeView(notice: notice)
            }
            if isLatest, !turn.isRunning {
                ending
            }
        }
    }

    @ViewBuilder private func activityRow(_ row: TranscriptRow) -> some View {
        switch row {
        case .toolGroup(let group):
            ToolGroupView(group: group, isLive: turn.isRunning && group.isRunning)
        // Polling only waits on the call before it, whose row stands for both.
        case .item(.toolCall(let call)) where call.isPolling:
            EmptyView()
        case .item(.toolCall(let call)):
            ToolCallView(call: call) { option in choose(option, for: call) }
        case .item:
            EmptyView()
        }
    }

    /// A turn that stopped short says so and offers the question again.
    @ViewBuilder private var ending: some View {
        switch turn.stopReason {
        case .error?:
            Button("Ask Again", systemImage: "arrow.clockwise") { Task { await conversation.askAgain() } }
                .buttonStyle(.ds(.secondary))
                .help("Sends your last question again")
        case .cancelled?:
            HStack(spacing: DS.Space.md) {
                Text(turn.answer.isEmpty ? "Stopped before answering." : "Stopped.")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                Button("Ask Again") { Task { await conversation.askAgain() } }
                    .buttonStyle(.ds(.ghost))
            }
        default:
            EmptyView()
        }
    }

    private func choose(_ option: PermissionOption, for call: ToolCallState) {
        guard let session = conversation.session else { return }
        Task { await session.choose(option, forToolCall: call.id) }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask turn") {
    let app = AppModel.preview()
    let center = PullRequestAskPreviewFixtures.center()
    let conversation = center.conversation(for: PullRequestPreviewRunner.reference)
    let turns = PullRequestAskPreviewFixtures.turns(in: app)
    return DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ForEach(turns) { turn in
                PullRequestAskTurnView(conversation: conversation, turn: turn, isLatest: true)
            }
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
    .environment(center)
    .environment(app)
}
#endif
