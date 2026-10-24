import SwiftUI

/// The strip along the window's bottom edge, dressed like the rest of the window's chrome: it
/// continues the sidebar column under a hairline (the column's own look at the user's transparency,
/// so the two read as one band), at the sidebar footer's height, with its items in quiet tertiary
/// caption text and hairlines between them. When the window is too narrow for every item, whole
/// items drop out, the leading end's innermost first, so nothing is ever cut mid-word.
///
/// Each top-level view in `leading` and `trailing` is one item. Make clickable items buttons with
/// `.statusBarSegment()`, and their glyphs `StatusBarGlyph`s.
public struct StatusBarSurface<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        StatusBarItemsLayout(spacing: DS.StatusBar.itemSpacing) {
            items(leading, at: .leading)
            items(trailing, at: .trailing)
        }
        .font(.dsCaption)
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(.dsTextTertiary)
        .padding(.horizontal, DS.StatusBar.edgeInset)
        .frame(maxWidth: .infinity)
        .frame(height: DS.Size.chromeBar)
        // Dropped items wait just past the trailing edge.
        .clipped()
        // The column's look the whole width, under the content too: the bar is the window's chrome,
        // its items belong to the whole window, and one band frames the content as a pane.
        .background {
            SidebarColumnBackdrop()
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) { SeparatorLine() }
    }

    private func items(_ content: some View, at edge: HorizontalEdge) -> some View {
        Group(subviews: content) { items in
            ForEach(items) { item in
                if item.id != items.first?.id {
                    StatusBarSeparator()
                        .layoutValue(key: StatusBarSlot.self, value: .separator(edge))
                }
                item.layoutValue(key: StatusBarSlot.self, value: .item(edge))
            }
        }
    }
}

extension DS {
    /// The status bar's own spacing. Its height is `DS.Size.chromeBar`.
    public enum StatusBar {
        /// Between the window's edges and the outermost items.
        public static let edgeInset = Space.lg
        /// On each side of the hairline between two items.
        public static let itemSpacing = Space.md
        /// The hairline between items: about the caption's cap-to-descender height.
        public static let separatorHeight: CGFloat = 12
    }
}

#if DEBUG
#Preview("Status bar") {
    DSPreviewPair {
        GalleryStatusBar()
            .padding(DS.Space.xl)
    }
}
#endif
