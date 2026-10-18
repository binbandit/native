import ACP
import SwiftUI

/// One file or image going out with the draft: its thumbnail or icon, name and size. Clicking it
/// (or Space when it has focus) opens it in Quick Look; the cross takes it off the message.
struct ComposerAttachmentChip: View {
    let attachment: PromptAttachment
    let onPreview: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Button(action: onPreview) {
                HStack(spacing: DS.Space.sm) {
                    AttachmentGlyph(attachment: attachment)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(attachment.name)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextPrimary)
                            .truncationMode(.middle)
                        Text(detail)
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    .lineLimit(1)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Quick Look \(attachment.name)")
            .accessibilityLabel("\(attachment.name), \(detail)")
            .accessibilityHint("Opens it in Quick Look")

            Button("Remove \(attachment.name)", systemImage: "xmark", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: ComposerMetrics.rowActionSize, height: ComposerMetrics.rowActionSize)
                .contentShape(.rect)
                .dsHitTarget(DS.Size.controlXS)
                .help("Remove from this message")
        }
        .padding(.leading, DS.Space.xs)
        .padding(.trailing, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: ComposerMetrics.attachmentChipMaxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(.dsFill, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(.dsBorder)
        }
    }

    /// "Image · 1.2 MB", "Folder", "Text · 4 KB".
    private var detail: String {
        let kind =
            switch attachment.content {
            case .image: "Image"
            case .text: "Text"
            case .reference: attachment.byteCount == nil ? "Folder" : "File"
            }
        guard let bytes = attachment.byteCount else { return kind }
        return "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))"
    }
}

/// The chip's leading square: the image itself, or a symbol for the kind of file.
private struct AttachmentGlyph: View {
    let attachment: PromptAttachment

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        Group {
            if case .image(let data, _) = attachment.content {
                AttachmentImage(data: data, maxSide: ComposerMetrics.attachmentThumbnail)
            } else {
                Image(systemName: symbol)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.dsBackground)
            }
        }
        .frame(width: ComposerMetrics.attachmentThumbnail, height: ComposerMetrics.attachmentThumbnail)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.dsBorder) }
    }

    private var symbol: String {
        switch attachment.content {
        case .image: "photo"
        case .text: "doc.text"
        case .reference: attachment.byteCount == nil ? "folder" : "doc"
        }
    }
}
