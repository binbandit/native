import ACP
import SwiftUI

/// The Bubbles experiment: the conversation as chat bubbles. The user's messages sit on the
/// trailing side in the accent color, the agent's on the leading side, grouped with a tail on the
/// last of each run. Tool activity sits in trays between bubbles, and requests that need the user
/// keep the standard approval card and its shortcuts.
nonisolated struct BubbleTranscriptStyle: TranscriptStyle {
    @MainActor func makeBody(_ transcript: TranscriptStyleConfiguration) -> some View {
        BubbleTranscript(transcript: transcript)
    }
}

private struct BubbleTranscript: View {
    let transcript: TranscriptStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLoading: Bool {
        transcript.session.phase == .loading
    }

    /// The agent is typing, not waiting on the user to answer a request.
    private var isTyping: Bool {
        transcript.isWorking && transcript.shortcutTarget == nil
    }

    var body: some View {
        let rows = BubbleRow.plan(transcript.rows)
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                BubbleRowView(row: row, transcript: transcript)
                    .padding(.top, index == 0 ? 0 : BubbleRow.spacing(between: rows[index - 1], and: row))
                    .transition(transition(for: row))
            }
            if isTyping {
                BubbleTypingIndicator()
                    .padding(.top, rows.isEmpty ? 0 : BubbleMetrics.rowSpacing)
                    .transition(reduceMotion ? .opacity : AnyTransition(RevealTransition()))
            }
        }
        // New rows slide in as they arrive, but not while history replays.
        .animation(isLoading ? nil : .bouncy(duration: 0.4, extraBounce: 0.05), value: rows.map(\.id))
        .animation(.smooth(duration: 0.25), value: isTyping)
        .onChange(of: transcript.rows.map(\.id), initial: true) { old, new in
            BubbleClock.shared.note(new, live: old != new && !isLoading)
        }
    }

    /// A sent message rises from the composer into place; everything else fades up.
    private func transition(for row: BubbleRow) -> AnyTransition {
        if reduceMotion {
            return .opacity
        }
        if row.bubbleSide == .trailing {
            return .asymmetric(insertion: AnyTransition(BubbleSendTransition()), removal: .opacity)
        }
        return .asymmetric(insertion: AnyTransition(RevealTransition()), removal: .opacity)
    }
}

private struct BubbleRowView: View {
    let row: BubbleRow
    let transcript: TranscriptStyleConfiguration

    var body: some View {
        switch row {
        case .message(let message, let side, let position):
            // Measuring Markdown's lists and tables at their ideal width leaves them a stale height,
            // so only one-line replies hug; anything with structure takes the full share.
            BubbleLane(side: side, hugsContent: side == .trailing || !message.text.contains("\n")) {
                BubbleMessageView(message: message, side: side, position: position)
            }
        case .thought(let message):
            agentSide {
                MessageView(message: message)
                    .padding(.leading, BubbleMetrics.horizontalPadding)
            }
        case .activity(let rows):
            agentSide {
                BubbleActivityTray {
                    ForEach(rows) { row in
                        switch row {
                        case .exploration(let calls): transcript.exploration(calls)
                        case .item(.toolCall(let call)): transcript.toolCall(call)
                        // Trays only hold tool activity.
                        case .item: EmptyView()
                        }
                    }
                }
            }
        case .approval(let call):
            agentSide {
                BubbleActivityTray { transcript.toolCall(call) }
            }
        case .notice(let notice):
            NoticeView(notice: notice)
        case .subagent(let subagent):
            agentSide { transcript.subagent(subagent) }
        case .sessionMessage(let message):
            agentSide { transcript.sessionMessage(message) }
        }
    }

    /// Lines content up with the agent's bubbles, past the strip their tails use.
    private func agentSide(@ViewBuilder _ content: () -> some View) -> some View {
        BubbleLane(side: .leading) {
            content()
                .padding(.leading, BubbleMetrics.tailWidth)
        }
    }
}

/// A sent bubble rises from below and settles in from its trailing corner.
private struct BubbleSendTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(y: phase.isIdentity ? 0 : 24)
            .scaleEffect(phase.isIdentity ? 1 : 0.9, anchor: .bottomTrailing)
    }
}
