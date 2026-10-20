import SwiftUI

/// The user's question, trailing, in the transcript's prompt bubble. A queued one says so.
struct PullRequestAskQuestionBubble: View {
    let text: String
    var isQueued = false

    var body: some View {
        VStack(alignment: .trailing, spacing: DS.Space.xs) {
            // As typed: Markdown syntax in a question stays literal.
            Text(verbatim: text)
                .font(.dsCallout)
                .foregroundStyle(.dsTextPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)
                .background(.dsFill, in: .rect(cornerRadius: TranscriptMetrics.promptBubbleRadius, style: .continuous))
                .opacity(isQueued ? 0.7 : 1)
            if isQueued {
                Text("Queued: goes out when this answer ends")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, DS.Space.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isQueued ? "Queued question: \(text)" : "You asked: \(text)")
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask question bubbles") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.md) {
            PullRequestAskQuestionBubble(text: "What does this change, and what's risky?")
            PullRequestAskQuestionBubble(
                text:
                    "And what should I test before approving this? I mostly care about the non-steering agents, since that's where Send Now stops the turn first.",
                isQueued: true)
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
}
#endif
