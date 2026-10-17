import SwiftUI

/// An attachment or context chip above the editor (the reference app `AttachmentPreview` chip): 28pt, 4pt
/// radius, outlined on a selected-tone fill, with a round remove button that turns accent on hover.
public struct ComposerChip: View {
    let title: String
    let systemImage: String?
    let onRemove: (() -> Void)?

    @State private var isRemoveHovered = false

    public init(_ title: String, systemImage: String? = nil, onRemove: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.onRemove = onRemove
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: DS.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.dsTextSecondary)
            }
            Text(title)
                .font(.dsBody)
                .tracking(DS.Tracking.tight)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let onRemove {
                Button("Remove \(title)", systemImage: "xmark", action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(isRemoveHovered ? .dsTextOnAccent : .dsTextTertiary)
                    .frame(width: 16, height: 16)
                    .background(isRemoveHovered ? Color.dsAccent : .clear, in: .circle)
                    .contentShape(.circle)
                    .dsHitTarget(16)
                    .trackHover($isRemoveHovered)
                    .help("Remove")
            }
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, onRemove == nil ? DS.Space.md : DS.Space.xs)
        .frame(height: DS.Size.composerPill)
        .frame(maxWidth: 240, alignment: .leading)
        .background(.dsSelected, in: shape)
        .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
        .fixedSize()
    }
}

#Preview("Chips") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xs) {
            ComposerChip("ComposerView.swift", systemImage: "doc.text") {}
            ComposerChip("Selection: 12 lines", systemImage: "text.cursor") {}
            ComposerChip("No remove button")
        }
    }
}
