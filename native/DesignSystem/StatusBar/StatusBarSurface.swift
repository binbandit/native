import SwiftUI

/// The strip along the window's bottom edge: Orca's status bar, dressed as Factory and
/// Conductor dress their chrome. It sits on the sidebar's translucent backdrop under a hairline,
/// at the sidebar footer's height, with its items in quiet tertiary caption text and hairlines
/// between them. When the window is too narrow for every item, whole items drop out, the leading
/// end's innermost first, so nothing is ever cut mid-word.
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
        .frame(height: DS.Window.footerHeight)
        // Dropped items wait just past the trailing edge.
        .clipped()
        .dsSidebarBackground()
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
    /// The status bar's own spacing. Its height is `DS.Window.footerHeight`.
    public enum StatusBar {
        /// Between the window's edges and the outermost items (Orca `px-3`).
        public static let edgeInset = Space.lg
        /// On each side of the hairline between two items.
        public static let itemSpacing = Space.md
        /// The hairline between items: about the caption's cap-to-descender height.
        public static let separatorHeight: CGFloat = 12
    }
}

#Preview("Status bar") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ForEach([CGFloat(720), 420, 240], id: \.self) { width in
                StatusBarSurface {
                    Button {
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            StatusIndicator(status: .working, size: DS.Size.statusGlyph)
                            Text("2 working")
                            Text("4m").foregroundStyle(.dsTextQuaternary)
                        }
                    }
                    .buttonStyle(.statusBarSegment())
                    Button {
                    } label: {
                        HStack(spacing: DS.Space.sm) {
                            StatusIndicator(status: .needsPermission, size: DS.Size.statusGlyph)
                            Text("1 needs you")
                        }
                    }
                    .buttonStyle(.statusBarSegment(.attention))
                    Text("Claude 38% · 5h")
                } trailing: {
                    Button {
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            StatusBarGlyph("cup.and.saucer")
                            Text("Off")
                        }
                    }
                    .buttonStyle(.statusBarSegment())
                    Button {
                    } label: {
                        HStack(spacing: DS.Space.xs) {
                            StatusBarGlyph("memorychip")
                            Text("764.1 MB")
                            StatusBarDivider()
                            StatusBarGlyph("cpu")
                            Text("3%")
                        }
                    }
                    .buttonStyle(.statusBarSegment(isActive: true))
                }
                .frame(width: width)
            }
        }
        .padding(DS.Space.xl)
    }
}
