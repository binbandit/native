import ACP
import SwiftUI

/// Images and files share a footprint, so a file never floats beside a taller image.
struct UserMessageAttachmentTile: View {
    let attachment: MessageAttachment
    var isSingle = false

    @Environment(\.openTranscriptArtifact) private var openArtifact

    private var artifact: TranscriptArtifact { TranscriptArtifact(attachment) }
    private var hasImage: Bool { artifact.isImage && artifact.hasImageHeader }

    var body: some View {
        Button {
            openArtifact?.open(artifact)
        } label: {
            if isSingle, hasImage, let data = artifact.data {
                AttachmentImage(
                    data: data, maxSide: DS.Artifact.thumbnailWidth,
                    fitting: CGSize(width: DS.Artifact.thumbnailWidth, height: DS.Artifact.thumbnailHeight))
            } else {
                tileContent
                    .frame(idealWidth: DS.Artifact.messageTileWidth, maxWidth: DS.Artifact.messageTileWidth)
                    .frame(height: DS.Artifact.messageTileHeight)
            }
        }
        .buttonStyle(UserMessageAttachmentButtonStyle())
        .disabled(openArtifact == nil)
        .help("Open \(attachment.name)")
        .accessibilityLabel("Open \(attachment.name)")
        .accessibilityValue(hasImage ? "Image" : detail)
        .accessibilityHint("Opens the artifact viewer")
        .contextMenu {
            Button("Open", systemImage: "eye") { openArtifact?.open(artifact) }
        }
    }

    @ViewBuilder private var tileContent: some View {
        if hasImage, let data = artifact.data {
            AttachmentImage(data: data, maxSide: DS.Artifact.messageTileWidth)
        } else {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Image(systemName: artifact.isImage ? "photo" : artifact.isFolder ? "folder" : "doc")
                    .font(.dsTitle3)
                    .foregroundStyle(.dsTextSecondary)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(verbatim: attachment.name)
                        .font(.dsBodyMedium)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(detail)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(1)
                }
            }
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var detail: String {
        if artifact.isFolder { return "Folder" }
        if let bytes = attachment.byteCount ?? artifact.data?.count, bytes >= 0 {
            return DSFormat.fileSize(bytes)
        }
        return artifact.isImage ? "Image" : "Size unavailable"
    }
}

private struct UserMessageAttachmentButtonStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.message, style: .continuous)
        configuration.label
            .background(.dsFill)
            .overlay { shape.fill(configuration.isPressed ? .dsPressed : isHovered ? .dsHover : .clear) }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.dsBorder) }
            .contentShape(shape)
            .dsFocusShape(shape)
            .trackHover($isHovered)
    }
}

#if DEBUG
#Preview("User attachment tiles - File details") {
    DSPreviewPair {
        HStack(spacing: DS.Space.sm) {
            ForEach(UserMessageAttachmentsPreviewFixtures.files) { attachment in
                UserMessageAttachmentTile(attachment: attachment)
            }
        }
        .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
    }
}
#endif
