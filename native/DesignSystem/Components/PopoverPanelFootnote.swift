import SwiftUI

/// A popover panel's closing note, under a hairline: what its numbers mean.
public struct PopoverPanelFootnote: View {
    let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(spacing: 0) {
            SeparatorLine()
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Space.lg)
                .padding(.vertical, DS.Space.md)
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Popover footnote") {
    DSPreviewPair {
        PopoverPanelFootnote("Counts come from the agents' own usage reports and reset on their schedule.")
            .frame(width: DS.Size.hoverCardWidth)
    }
}
#endif
