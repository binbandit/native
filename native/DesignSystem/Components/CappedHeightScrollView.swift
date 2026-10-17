import SwiftUI

/// Shows its content at natural height up to `maxHeight`, then scrolls: plans, slash-command lists,
/// tool output. It measures the content, because a scroll view on its own always wants all the
/// height it's offered.
public struct CappedHeightScrollView<Content: View>: View {
    let maxHeight: CGFloat
    let content: Content

    @State private var contentHeight: CGFloat?

    public init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.maxHeight = maxHeight
        self.content = content()
    }

    public var body: some View {
        ScrollView(.vertical) {
            content
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: contentHeight.map { min($0, maxHeight) } ?? maxHeight)
    }
}

#Preview("Capped height") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            ForEach([3, 30], id: \.self) { count in
                CappedHeightScrollView(maxHeight: 160) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<count, id: \.self) { index in
                            Text("Row \(index + 1)")
                                .font(.dsBody)
                                .foregroundStyle(.dsTextSecondary)
                                .frame(height: DS.Size.listRow)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 140)
                .background(.dsSurface)
            }
        }
    }
}
