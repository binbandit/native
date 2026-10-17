import ACP
import SwiftUI

/// One message as a bubble: the user's in the accent color, the agent's in a neutral wash with its
/// Markdown rendered as in the standard transcript. Hovering or tapping shows when it arrived.
struct BubbleMessageView: View {
    let message: TranscriptMessage
    let side: BubbleSide
    let position: BubbleGroupPosition

    @Environment(\.dsAccentPalette) private var palette
    @State private var isHovering = false
    @State private var showsTime = false

    var body: some View {
        content
            .padding(.vertical, BubbleMetrics.verticalPadding)
            .padding(.leading, BubbleMetrics.horizontalPadding + (side == .leading ? BubbleMetrics.tailWidth : 0))
            .padding(.trailing, BubbleMetrics.horizontalPadding + (side == .trailing ? BubbleMetrics.tailWidth : 0))
            .background(side == .trailing ? BubblePalette.outgoing(palette) : BubblePalette.incoming, in: shape)
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
                .foregroundStyle(BubblePalette.outgoingText(palette))
                .textSelection(.enabled)
        case .leading:
            MarkdownView(message.text)
        }
    }

    /// The time beside the bubble, in the empty space on the other side. A zero-width frame at the
    /// bubble's edge lets the label overflow outward without taking any room.
    @ViewBuilder private var timestamp: some View {
        // Replayed history has no times, so its bubbles show none rather than a wrong one.
        if isHovering || showsTime, let date = message.startedAt {
            Text(date, style: .time)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize()
                .padding(side == .trailing ? .trailing : .leading, BubbleMetrics.timestampSpacing)
                .padding(.bottom, BubbleMetrics.verticalPadding)
                .frame(width: 0, alignment: side == .trailing ? .trailing : .leading)
                .transition(.opacity)
                .accessibilityHidden(true)
        }
    }
}
