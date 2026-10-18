import ACP
import QuickLook
import SwiftUI

/// The files and images that went with a user's message, trailing above its text: images as
/// thumbnails that open in Quick Look, files as chips that show the file in the Finder.
struct MessageAttachmentsView: View {
    let attachments: [MessageAttachment]

    @State private var previewing: URL?

    var body: some View {
        let images = attachments.filter(\.isImage)
        let files = attachments.filter { !$0.isImage }
        VStack(alignment: .trailing, spacing: DS.Space.sm) {
            if !images.isEmpty {
                HStack(spacing: DS.Space.sm) {
                    ForEach(images) { image in
                        imageTile(image)
                    }
                }
            }
            if !files.isEmpty {
                HStack(spacing: DS.Space.sm) {
                    ForEach(files) { file in
                        fileChip(file)
                    }
                }
            }
        }
        .quickLookPreview($previewing)
    }

    private func imageTile(_ attachment: MessageAttachment) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return Button {
            previewing = attachment.previewURL
        } label: {
            if let data = attachment.imageData {
                AttachmentImage(
                    data: data, maxSide: TranscriptMetrics.attachmentImageMaxWidth,
                    fitting: CGSize(
                        width: TranscriptMetrics.attachmentImageMaxWidth,
                        height: TranscriptMetrics.attachmentImageHeight)
                )
                .clipShape(shape)
                .overlay { shape.strokeBorder(.dsBorder) }
                .contentShape(shape)
            }
        }
        .buttonStyle(.plain)
        .help("Quick Look \(attachment.name)")
        .accessibilityLabel("Image \(attachment.name)")
        .accessibilityHint("Opens it in Quick Look")
    }

    private func fileChip(_ attachment: MessageAttachment) -> some View {
        let canReveal = PlatformFileBrowser.canReveal && attachment.url?.isFileURL == true
        return Button {
            if let url = attachment.url { PlatformFileBrowser.reveal(url) }
        } label: {
            Label(attachment.name, systemImage: "doc")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .background(.dsFill, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canReveal)
        .help(attachment.url.map { "Show \($0.path(percentEncoded: false)) in the Finder" } ?? attachment.name)
    }
}

extension MessageAttachment {
    /// A file Quick Look can open: the image's own file while it's still there, else a copy of the
    /// bytes the message carried.
    var previewURL: URL? {
        if let url, url.isFileURL, FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            return url
        }
        guard let imageData else { return nil }
        let copy = URL.temporaryDirectory.appending(path: "Native Attachments/\(id.uuidString)/\(name).png")
        try? FileManager.default.createDirectory(
            at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? imageData.write(to: copy)
        return copy
    }
}
