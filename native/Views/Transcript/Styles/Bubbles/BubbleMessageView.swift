import ACP
import SwiftUI

/// One message as a bubble: the user's in the accent color, the agent's in a neutral wash with its
/// Markdown rendered as in the standard transcript. Hovering or tapping shows when it arrived.
struct BubbleMessageView: View {
    let message: TranscriptMessage
    let side: BubbleSide
    let position: BubbleGroupPosition

    @State private var isHovering = false
    @State private var showsTime = false

    var body: some View {
        content
            .padding(.vertical, BubbleMetrics.verticalPadding)
            .padding(.leading, BubbleMetrics.horizontalPadding + (side == .leading ? BubbleMetrics.tailWidth : 0))
            .padding(.trailing, BubbleMetrics.horizontalPadding + (side == .trailing ? BubbleMetrics.tailWidth : 0))
            .background(side == .trailing ? BubblePalette.outgoing : BubblePalette.incoming, in: shape)
            // Code blocks inside round concentrically with the bubble.
            .containerShape(.rect(cornerRadius: BubbleMetrics.radius, style: .continuous))
            .contentShape(shape)
            .overlay(alignment: side == .trailing ? .bottomLeading : .bottomTrailing) {
                timestamp
            }
            .onHover { isHovering = $0 }
            // Simultaneous, so clicks still select text.
            .simultaneousGesture(TapGesture().onEnded { showsTime.toggle() })
            .animation(.dsQuick, value: isHovering || showsTime)
    }

    private var shape: BubbleShape {
        BubbleShape(side: side, position: position)
    }

    @ViewBuilder private var content: some View {
        switch side {
        case .trailing:
            // Prompts are shown as typed; Markdown syntax in them stays literal.
            Text(verbatim: message.text)
                .foregroundStyle(BubblePalette.outgoingText)
                .textSelection(.enabled)
        case .leading:
            MarkdownView(message.text)
        }
    }

    /// The time beside the bubble, in the empty space on the other side.
    @ViewBuilder private var timestamp: some View {
        if isHovering || showsTime, let date = BubbleClock.shared.date(for: TranscriptItem.message(message).id) {
            Text(date, style: .time)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize()
                .padding(.bottom, BubbleMetrics.verticalPadding)
                .alignmentGuide(side == .trailing ? .leading : .trailing) { dimensions in
                    side == .trailing
                        ? dimensions.width + BubbleMetrics.timestampSpacing : -BubbleMetrics.timestampSpacing
                }
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}
