import SwiftUI

// The composer's frame, matched to the reference app's composer (`ChatComposer`, `ComposerStackSection`).
// Measured from the reference app at 1x: sections share 1pt #3e3e3e rules inside a 4pt-rounded outline, the
// text sits 8x12pt in at 13pt, and the controls row is inset 8pt with 8pt between 28pt pills.

extension DS {
    /// Composer metrics.
    public nonisolated enum Composer {
        /// Padding around the text editor (the reference app `EditableArea`: 8pt by 12pt).
        public static let textInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        /// Padding around a row of controls (the reference app `ComposerStackSection p="md"`).
        public static let controlsInset: CGFloat = 8
        /// Space between pills (8pt measured: the reference app's 4pt gap plus the model pill's margin).
        public static let controlSpacing: CGFloat = 8
        /// Space between a pill's text and its outline.
        public static let pillPadding: CGFloat = 10
        /// The editor's line height multiple (the reference app 1.5).
        public static let lineHeight: CGFloat = 1.5
    }
}

/// The composer's container: each child is a section, stacked with 1pt rules between them inside a
/// single outlined, 4pt-rounded surface (the reference app `ComposerStackSection`). Put the editor in one
/// section and `ComposerControlsBar` in the next; plans, approvals and attachments go above.
public struct ComposerSurface<Content: View>: View {
    let isFloating: Bool
    let isDropTargeted: Bool
    let content: Content

    /// - Parameters:
    ///   - isFloating: The composer floats over scrolling content: Liquid Glass replaces the solid
    ///     fill (glass is for the control layer only).
    ///   - isDropTargeted: Files are dragged over it: a dashed accent outline (the reference app's drop state).
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
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.dsSurface, in: shape)
        }
    }
}

/// The composer's bottom row: pickers and toggles leading (scrolling sideways when they don't fit,
/// as in the reference app), the voice or other actions trailing; inset 8pt with 8pt between controls.
public struct ComposerControlsBar<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

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
