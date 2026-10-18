import SwiftUI

/// The layout of a popover that explains something (Orca's Resource Manager): a header with a
/// glyph, a title and actions on the right, a hairline, then the content. Present it with
/// `.dsPopover`, which gives it the overlay backdrop.
public struct PopoverPanel<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String?
    let width: CGFloat
    let accessory: Accessory
    let content: Content

    public init(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = DS.Size.popoverWidth,
        @ViewBuilder accessory: () -> Accessory,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.width = width
        self.accessory = accessory()
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.dsCaptionMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: DS.Space.md)
                accessory
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.lg)
            .frame(height: DS.Size.controlMD)
            SeparatorLine()
            content
        }
        .frame(width: width)
    }
}

extension PopoverPanel where Accessory == EmptyView {
    public init(
        title: String,
        systemImage: String? = nil,
        width: CGFloat = DS.Size.popoverWidth,
        @ViewBuilder content: () -> Content
    ) {
        self.init(title: title, systemImage: systemImage, width: width, accessory: { EmptyView() }, content: content)
    }
}

extension View {
    /// Presents a popover the design system's way: on the overlay backdrop at the user's
    /// transparency, and still a popover (not a sheet) in a compact iPad window. Its text starts
    /// from the body style, whatever its anchor's (a status-bar item's one-line caption, say).
    public func dsPopover(
        isPresented: Binding<Bool>,
        arrowEdge: Edge = .top,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) {
            content()
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(nil)
                .dsPopoverBackground()
                .presentationCompactAdaptation(.popover)
        }
    }
}

#Preview("Popover panel") {
    DSPreviewPair {
        PopoverPanel(title: "Memory and CPU", systemImage: "memorychip", width: 320) {
            Text("764.1 MB")
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                Text("Claude Code")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(DS.Space.lg)
                PopoverPanelFootnote("Memory is each process's footprint, as Activity Monitor shows it.")
            }
        }
        .dsOverlayBackground(in: .rect(cornerRadius: DS.Radius.panel))
    }
}
