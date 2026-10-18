import SwiftUI

// The composer's frame: sections share 1pt #3e3e3e rules inside a 4pt-rounded outline, the text
// sits 8x12pt in at 13pt, and the controls row is inset 8pt with 8pt between 28pt pills.

extension DS {
    /// Composer metrics.
    public nonisolated enum Composer {
        /// Padding around the text editor: 8pt by 12pt.
        public static let textInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        /// Padding around a row of controls.
        public static let controlsInset: CGFloat = 8
        /// Space between pills.
        public static let controlSpacing: CGFloat = 8
        /// Space between a pill's text and its outline.
        public static let pillPadding: CGFloat = 10
        /// The editor's line height multiple.
        public static let lineHeight: CGFloat = 1.5
        /// How far the controls row fades out at an edge that has more controls past it.
        public static let edgeFade: CGFloat = 24
    }
}

/// The composer's container: each child is a section, stacked with 1pt rules between them inside a
/// single outlined, 4pt-rounded surface. Put the editor in one
/// section and `ComposerControlsBar` in the next; plans, approvals and attachments go above.
public struct ComposerSurface<Content: View>: View {
    let isFloating: Bool
    let isDropTargeted: Bool
    let content: Content

    /// - Parameters:
    ///   - isFloating: The composer floats over scrolling content: Liquid Glass replaces the solid
    ///     fill, as see-through as the user's transparency (glass is for the control layer only).
    ///   - isDropTargeted: Files are dragged over it: a dashed accent outline.
    public init(isFloating: Bool = false, isDropTargeted: Bool = false, @ViewBuilder content: () -> Content) {
        self.isFloating = isFloating
        self.isDropTargeted = isDropTargeted
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { sections in
                ForEach(sections) { section in
                    if section.id != sections.first?.id {
                        Rectangle()
                            .fill(.dsBorder)
                            .frame(height: 1)
                    }
                    section
                }
            }
        }
        .modifier(ComposerBackground(isFloating: isFloating, shape: shape))
        .clipShape(shape)
        .overlay {
            if isDropTargeted {
                shape.strokeBorder(.dsAccent, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            } else {
                shape.strokeBorder(.dsBorder, lineWidth: 1)
            }
        }
        .containerShape(shape)
    }
}

private struct ComposerBackground: ViewModifier {
    let isFloating: Bool
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if isFloating {
            content.dsGlassEffect(in: shape)
        } else {
            content.background(.dsSurface, in: shape)
        }
    }
}

/// The composer's bottom row: pickers and toggles leading (scrolling sideways when they don't fit,
/// and fading at an edge with more past it), the voice or other actions trailing;
/// inset 8pt with 8pt between controls.
public struct ComposerControlsBar<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing
    /// The edges with controls scrolled past them, which fade rather than cut a pill in half.
    @State private var hiddenEdges = HorizontalEdge.Set()

    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: DS.Composer.controlSpacing) {
            ScrollView(.horizontal) {
                HStack(spacing: DS.Composer.controlSpacing) {
                    leading
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onScrollGeometryChange(for: HorizontalEdge.Set.self) { geometry in
                var edges = HorizontalEdge.Set()
                if geometry.contentOffset.x > 1 { edges.insert(.leading) }
                if geometry.contentOffset.x + geometry.containerSize.width < geometry.contentSize.width - 1 {
                    edges.insert(.trailing)
                }
                return edges
            } action: { _, edges in
                hiddenEdges = edges
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: hiddenEdges.contains(.leading) ? DS.Composer.edgeFade : 0)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: hiddenEdges.contains(.trailing) ? DS.Composer.edgeFade : 0)
                }
                .animation(.dsQuick, value: hiddenEdges)
            }
            trailing
        }
        .padding(DS.Composer.controlsInset)
    }
}

extension ComposerControlsBar where Trailing == EmptyView {
    public init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading) { EmptyView() }
    }
}

#Preview("Composer") {
    DSPreviewPair {
        GalleryComposer()
            .frame(width: 640)
    }
}
