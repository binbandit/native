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

    /// The agent is typing, not waiting on the user for an approval, an answer or a plan review
    /// (`SessionModel.taskStatus`, which the sidebar and status bar read too).
    private var isTyping: Bool {
        transcript.isWorking && !transcript.session.taskStatus.needsAttention
    }

    var body: some View {
        // A usage limit shows once, as a card where the work stopped, in place of the messages saying so.
        let limitStops = transcript.session.state.usageLimitStops
        let rows = BubbleRow.plan(
            transcript.rows.filter { row in
                guard case .item(let item) = row, let entry = limitStops[item.id] else { return true }
                return entry.stop.anchorID == item.id
            })
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                BubbleRowView(row: row, transcript: transcript, limitStops: limitStops)
                    .padding(.top, index == 0 ? 0 : BubbleRow.spacing(between: rows[index - 1], and: row))
                    .sessionTranscriptLine(row.id)
                    .transition(transition(for: row))
            }
            if isTyping {
                BubbleTypingIndicator()
                    .environment(\.dsWorkingAnimation, transcript.session.workingAnimation)
                    .padding(.top, rows.isEmpty ? 0 : BubbleMetrics.rowSpacing)
                    .transition(reduceMotion ? .opacity : AnyTransition(RevealTransition()))
            }
        }
        // New rows slide in as they arrive, but not while history replays.
        .animation(isLoading ? nil : .bouncy(duration: 0.4, extraBounce: 0.05), value: rows.map(\.id))
        .animation(.smooth(duration: 0.25), value: isTyping)
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
    let limitStops: [String: (stop: UsageLimitStop, isLatestTurn: Bool)]

    var body: some View {
        switch row {
        case .message(let message, _, _) where limitStops[message.id.uuidString] != nil:
            limitCard(for: message.id.uuidString)
        case .notice(let notice) where limitStops[notice.id.uuidString] != nil:
            limitCard(for: notice.id.uuidString)
        case .message(let message, let side, let position):
            VStack(spacing: DS.Space.lg) {
                // Instructions that went ahead of a prompt (a mode's) show as a marker above it.
                if let marker = message.preamble {
                    PromptPreambleMarker(marker: marker)
                }
                BubbleLane(side: side, hugsContent: true) {
                    VStack(alignment: .trailing, spacing: DS.Space.sm) {
                        if !message.attachments.isEmpty {
                            MessageAttachmentsView(attachments: message.attachments)
                        }
                        if !message.text.isEmpty || message.attachments.isEmpty {
                            BubbleMessageView(message: message, side: side, position: position)
                        }
                    }
                }
            }
        case .thought(let message):
            agentSide {
                MessageView(message: message)
                    .padding(.leading, BubbleMetrics.horizontalPadding)
            }
        case .activity(let rows):
            agentSide(hugsContent: true) {
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

    @ViewBuilder private func limitCard(for itemID: String) -> some View {
        if let entry = limitStops[itemID] {
            agentSide {
                UsageLimitTranscriptCard(
                    session: transcript.session, stop: entry.stop, isLatestTurn: entry.isLatestTurn)
            }
        }
    }

    /// Lines content up with the agent's bubbles, past the strip their tails use. Hugging content
    /// sizes to it like a bubble; the rest takes the agent's full share.
    private func agentSide(hugsContent: Bool = false, @ViewBuilder _ content: () -> some View) -> some View {
        BubbleLane(side: .leading, hugsContent: hugsContent) {
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
