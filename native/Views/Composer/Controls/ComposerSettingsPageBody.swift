import SwiftUI

/// One scrolling region for a page's whole body, below its pinned header. Unlike a fixed-height
/// scroller, the flexible ideal height can shrink again on a short display. The content stays
/// mounted as its size changes, retaining server recovery notes and in-flight actions.
struct ComposerSettingsPageBody<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat?

    private var cappedHeight: CGFloat {
        let budget =
            DS.ComposerSettings.popoverMaxHeight - DS.ComposerSettings.popoverInset
            - DS.ComposerSettings.rowHeight - DS.Space.xs
        return min(contentHeight ?? budget, budget)
    }

    var body: some View {
        ScrollView(.vertical) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(minHeight: 0, idealHeight: cappedHeight, maxHeight: cappedHeight)
    }
}

#Preview("Task settings page - Short and overflow") {
    DSPreviewPair {
        HStack(alignment: .top) {
            ForEach([3, 18], id: \.self) { count in
                ComposerSettingsPageFrame(title: "MCP Servers", scrollsOverflow: true, onBack: {}) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(1...count, id: \.self) { index in
                            Text("Server \(index)")
                                .font(DS.ComposerSettings.rowFont)
                                .frame(height: DS.ComposerSettings.rowHeight)
                                .composerSettingsTextEdge()
                        }
                    }
                }
            }
        }
    }
}
