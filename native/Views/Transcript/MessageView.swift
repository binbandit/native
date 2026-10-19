import ACP
import NativeAutomation
import SwiftUI

/// A user prompt, an agent reply, or the agent's reasoning.
/// Equatable, so a message that didn't change doesn't re-render while another one streams.
struct MessageView: View, Equatable {
    let message: TranscriptMessage
    /// When reasoning started and, once the agent moved on, ended (`SessionState.thinkingInterval`).
    /// Without it a thought times itself from its first to its last chunk.
    var thinking: ThinkingClock?

    var body: some View {
        switch message.role {
        case .user where GoalPrompt(parsing: message.text) != nil:
            // Native's own goal prompts read as one quiet line, not a wall of instructions.
            if let goal = GoalPrompt(parsing: message.text) {
                GoalPromptRow(prompt: goal, text: message.text)
            }
        case .user where TaskPromptFrame(parsing: message.text) != nil:
            // A reloaded task session replays its task prompt and messages with Native's header on.
            if let frame = TaskPromptFrame(parsing: message.text) {
                SessionMessageView(frame: frame)
            }
        case .user:
            VStack(alignment: .trailing, spacing: DS.Space.sm) {
                if !message.attachments.isEmpty {
                    MessageAttachmentsView(attachments: message.attachments)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                if !message.text.isEmpty {
                    TrailingFractionLayout(fraction: 0.85) {
                        // Prompts are shown as typed: only their code reads as code.
                        let bubble = RoundedRectangle(
                            cornerRadius: TranscriptMetrics.promptBubbleRadius, style: .continuous)
                        UserMessageText(text: message.text)
                            .textSelection(.enabled)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.vertical, DS.Space.md)
                            .background(.dsFill, in: bubble)
                            .containerShape(bubble)
                    }
                }
            }
        case .agent:
            MarkdownView(message.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .thought:
            ThoughtView(
                id: message.id.uuidString,
                text: message.text,
                clock: thinking ?? message.startedAt.map { ThinkingClock(start: $0, end: message.updatedAt) })
        }
    }
}

struct NoticeView: View {
    let notice: TranscriptNotice

    var body: some View {
        Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle.fill" : "info.circle")
            .font(.dsCaption)
            .foregroundStyle(notice.isError ? Color.dsDanger : .dsTextSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
    }
}

/// The agent's reasoning, collapsed behind one quiet row named by a fact: "Thinking 4s…" with a
/// ticking count while it streams, "Thought for 12s" once it's done.
private struct ThoughtView: View {
    let id: String
    let text: String
    /// Nil for replayed history, which has no times.
    let clock: ThinkingClock?

    @Environment(TranscriptDisclosures.self) private var disclosures: TranscriptDisclosures?
    /// For thoughts shown outside a transcript, which has no `TranscriptDisclosures`.
    @State private var isOpenHere = false

    private var isExpanded: Bool {
        disclosures?.isOpen(id) ?? isOpenHere
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Button {
                withAnimation(.dsDisclosure) {
                    if let disclosures {
                        disclosures.toggle(id)
                    } else {
                        isOpenHere.toggle()
                    }
                }
            } label: {
                HStack(spacing: DS.Space.sm) {
                    label
                    DisclosureChevron(isExpanded: isExpanded)
                }
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "expanded" : "collapsed")

            if isExpanded {
                MarkdownView(text)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.leading, DS.Space.lg)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(.dsTextQuaternary)
                            .frame(width: TranscriptMetrics.thoughtRailWidth)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var label: some View {
        if let clock, let end = clock.end {
            Text(DSFormat.thoughtFor(end.timeIntervalSince(clock.start)))
        } else if let clock {
            HStack(spacing: 0) {
                Text("Thinking ")
                ElapsedTimeText(since: clock.start)
                Text(verbatim: "…")
            }
            .shimmering(true)
        } else {
            // Replayed history doesn't say how long it took.
            Text("Thought")
        }
    }
}

/// When reasoning started and, once the agent moved on, ended; no end while it's still thinking.
struct ThinkingClock: Equatable {
    var start: Date
    var end: Date?
}

/// Fills the offered width and trailing-aligns its content, which gets at most `fraction` of it.
private struct TrailingFractionLayout: Layout {
    let fraction: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(childProposal(for: proposal))
        // An ideal or maximum measurement fills nothing: report the bubble itself, never infinity.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? size.width
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let childProposal = childProposal(for: ProposedViewSize(bounds.size))
        let size = child.sizeThatFits(childProposal)
        child.place(at: CGPoint(x: bounds.maxX, y: bounds.minY), anchor: .topTrailing, proposal: ProposedViewSize(size))
    }

    private func childProposal(for proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: proposal.width.map { $0.isFinite ? $0 * fraction : $0 }, height: nil)
    }
}

#if DEBUG
#Preview("Messages") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(TranscriptFixtures.messages, id: \.id) { message in
                MessageView(message: message)
            }
            ForEach(TranscriptFixtures.notices, id: \.id) { notice in
                NoticeView(notice: notice)
            }
        }
        .padding(20)
    }
    .frame(width: 640, height: 640)
}
#endif
