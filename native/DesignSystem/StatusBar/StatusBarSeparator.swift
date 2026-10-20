import SwiftUI

/// The short hairline `StatusBarSurface` puts between two items.
public struct StatusBarSeparator: View {
    public init() {}

    public var body: some View {
        SeparatorLine(axis: .vertical)
            .frame(height: DS.StatusBar.separatorHeight)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Status bar separator") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Text("Claude Code · 42%")
            StatusBarSeparator()
            Text("Codex · ready")
        }
        .font(.dsCaption)
        .foregroundStyle(.dsTextTertiary)
        .frame(height: DS.Size.chromeBar)
    }
}
#endif
