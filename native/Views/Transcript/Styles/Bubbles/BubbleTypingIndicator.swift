import SwiftUI

/// The agent's side while it works: a small bubble with the typing loader.
struct BubbleTypingIndicator: View {
    var body: some View {
        DotGridLoader(pattern: .typing)
            .frame(width: BubbleMetrics.typingDots, height: BubbleMetrics.typingDots)
            .foregroundStyle(.dsTextSecondary)
            .padding(.vertical, BubbleMetrics.verticalPadding)
            .padding(.leading, BubbleMetrics.horizontalPadding + BubbleMetrics.tailWidth)
            .padding(.trailing, BubbleMetrics.horizontalPadding)
            .background(BubblePalette.incoming, in: BubbleShape(side: .leading, position: .single))
            .accessibilityElement()
            .accessibilityLabel("Working")
            .help("Working…")
    }
}
