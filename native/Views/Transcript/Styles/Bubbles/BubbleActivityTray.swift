import SwiftUI

/// The agent's tool activity between bubbles: its rows, unchanged from the standard transcript, in
/// one quiet tray on the agent's side, so a run of calls reads as one aside.
struct BubbleActivityTray<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BubbleMetrics.trayRadius, style: .continuous)
        VStack(alignment: .leading, spacing: BubbleMetrics.trayRowSpacing) {
            content
        }
        .padding(.horizontal, BubbleMetrics.trayHorizontalPadding)
        .padding(.vertical, BubbleMetrics.trayVerticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BubblePalette.tray, in: shape)
        .overlay { shape.strokeBorder(BubblePalette.trayBorder) }
        .containerShape(shape)
    }
}
