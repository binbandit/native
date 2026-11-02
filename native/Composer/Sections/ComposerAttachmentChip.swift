import ACP
import SwiftUI

/// One file or image going out with the draft: its thumbnail or icon, name, and what the agent
/// gets. Clicking it (or Space when it has focus) opens it in Quick Look; the cross, Delete when it
/// has focus, or its context menu (a long press on iPad) takes it off the message.
struct ComposerAttachmentChip: View {
    let attachment: PromptAttachment
    /// Why a picture goes as its path instead of an image, if it does.
    let pathOnlyReason: String?
    /// Gone from disk since it was attached, found when the user tried to send.
    let isMissing: Bool
    /// Selected from the text with ←, so Delete takes it off.
    var isSelected = false
    let onPreview: () -> Void
    let onRemove: () -> Void

    var body: some View {
        // Only a file that can't go is outlined; a picture going as its path just says so.
        ComposerAttachmentChipFrame(state: isSelected ? .selected : isMissing ? .warning : .normal) {
            Button(action: onPreview) {
                HStack(spacing: DS.Space.sm) {
                    AttachmentGlyph(attachment: attachment, isWarning: isWarning)
                    ComposerAttachmentChipText(name: attachment.name, detail: detail, isWarning: isWarning)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel("\(attachment.name), \(detail)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isWarning ? help : "Opens it in Quick Look")
            .onDeleteKey(perform: onRemove)

            Button("Remove \(attachment.name)", systemImage: "xmark", action: onRemove)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.dsCaption)
                // A control, so it keeps 3:1 against the chip in every appearance.
                .foregroundStyle(.dsTextSecondary)
                .frame(width: ComposerMetrics.rowActionSize, height: ComposerMetrics.rowActionSize)
                .contentShape(.rect)
                .dsHitTarget(DS.Size.controlXS)
                .help("Remove from this message")
        }
        .contextMenu {
            Button("Quick Look", systemImage: "eye", action: onPreview)
            if PlatformFileBrowser.canReveal, !isMissing {
                Button("Show in Finder", systemImage: "folder") { PlatformFileBrowser.reveal(attachment.url) }
            }
            Divider()
            Button("Remove from Message", systemImage: "xmark", role: .destructive, action: onRemove)
        }
    }

    private var isWarning: Bool {
        isMissing || pathOnlyReason != nil
    }

    /// "Image · 1.2 MB", "Folder", "Text · 4 KB"; "Path only · 72 MB" for a picture that won't go as
    /// an image; "Moved or deleted" for one that's gone.
    private var detail: String {
        if isMissing { return "Moved or deleted" }
        let kind =
            switch attachment.content {
            case _ where pathOnlyReason != nil: "Path only"
            case .image: "Image"
            case .text: "Text"
            case .reference: attachment.byteCount == nil ? "Folder" : "File"
            }
        guard let bytes = attachment.byteCount else { return kind }
        return "\(kind) · \(DSFormat.fileSize(bytes))"
    }

    private var help: String {
        if isMissing { return "Moved or deleted since you attached it. Remove it, or attach it again." }
        return pathOnlyReason ?? "Quick Look \(attachment.name)"
    }
}

/// A file still being read, in the place its chip will take.
struct ComposerPendingAttachmentChip: View {
    let pending: ComposerPendingAttachment

    var body: some View {
        ComposerAttachmentChipFrame(state: .normal) {
            HStack(spacing: DS.Space.sm) {
                DotGridLoader(pattern: .waiting)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    .frame(width: ComposerMetrics.attachmentThumbnail, height: ComposerMetrics.attachmentThumbnail)
                    .background(.dsBackground, in: .rect(cornerRadius: DS.Radius.small, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous).strokeBorder(.dsBorder)
                    }
                ComposerAttachmentChipText(name: pending.name, detail: "Attaching…", isWarning: false)
            }
            // Where the cross will be, so the chip doesn't change width when it lands.
            .padding(.trailing, ComposerMetrics.rowActionSize + DS.Space.sm)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The chip's shape, shared by attached and pending files.
private struct ComposerAttachmentChipFrame<Content: View>: View {
    enum State {
        case normal
        /// Selected from the keyboard: the selected fill, outlined in the text color.
        case selected
        /// Outlined in the warning color, for a file that stops the message going.
        case warning
    }

    let state: State
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        HStack(spacing: DS.Space.sm) {
            content
        }
        .padding(.leading, DS.Space.xs)
        .padding(.trailing, DS.Space.sm)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: ComposerMetrics.attachmentChipMaxWidth, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .background(state == .selected ? Color.dsSelected : .dsFill, in: shape)
        .overlay { shape.strokeBorder(stroke) }
    }

    private var stroke: Color {
        switch state {
        case .normal: .dsBorder
        case .selected: .dsTextPrimary
        case .warning: .dsWarning
        }
    }
}

private struct ComposerAttachmentChipText: View {
    let name: String
    let detail: String
    let isWarning: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
                .truncationMode(.middle)
            Text(detail)
                .font(.dsCaption)
                .foregroundStyle(isWarning ? .dsWarning : .dsTextSecondary)
        }
        .lineLimit(1)
    }
}

/// The chip's leading square: the image itself, or a symbol for the kind of file.
private struct AttachmentGlyph: View {
    let attachment: PromptAttachment
    let isWarning: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        Group {
            if case .image(let data, _) = attachment.content {
                AttachmentImage(data: data, maxSide: ComposerMetrics.attachmentThumbnail)
            } else {
                Image(systemName: symbol)
                    .font(.dsBody)
                    .foregroundStyle(isWarning ? .dsWarning : .dsTextSecondary)
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
        case .reference where attachment.isImageFile: "photo"
        case .reference: attachment.byteCount == nil ? "folder" : "doc"
        }
    }
}

#if DEBUG
#Preview("Attachment chips") {
    let fixtures = ComposerPreviewFixtures.attachments
    let longName = PromptAttachment(
        url: URL(
            filePath: "/Users/preview/Developer/native/docs/decisions/2026-10-18-queue-follow-ups-while-a-turn-runs.md"),
        content: .text("# Decision\n"), byteCount: 9_200)
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(fixtures) { attachment in
                ComposerAttachmentChip(
                    attachment: attachment, pathOnlyReason: nil, isMissing: false, onPreview: {}, onRemove: {})
            }
            ComposerAttachmentChip(
                attachment: fixtures[0], pathOnlyReason: nil, isMissing: false, isSelected: true, onPreview: {},
                onRemove: {})
            ComposerAttachmentChip(
                attachment: fixtures[0], pathOnlyReason: nil, isMissing: true, onPreview: {}, onRemove: {})
            ComposerAttachmentChip(
                attachment: fixtures[1], pathOnlyReason: "Codex can’t take images, so it gets its path instead.",
                isMissing: false, onPreview: {}, onRemove: {})
            ComposerAttachmentChip(
                attachment: longName, pathOnlyReason: nil, isMissing: false, onPreview: {}, onRemove: {})
            ComposerPendingAttachmentChip(pending: ComposerPendingAttachment(name: "Simulator Screenshot.png"))
        }
    }
}
#endif
