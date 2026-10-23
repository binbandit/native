import ACP
import SwiftUI

/// Attached and returned artifacts share the same quiet thumbnails and opening action.
struct MessageAttachmentsView: View {
    let attachments: [MessageAttachment]
    var alignment: HorizontalAlignment = .trailing

    var body: some View {
        FlowLayout(spacing: DS.Space.sm, alignment: alignment) {
            ForEach(attachments) { attachment in
                ArtifactThumbnail(artifact: TranscriptArtifact(attachment))
            }
        }
    }
}

extension MessageAttachment {
    var isFolder: Bool {
        url?.hasDirectoryPath == true || name.hasSuffix("/")
    }
}

#if DEBUG
#Preview("Message attachments - Images and files") {
    DSPreviewPair {
        MessageAttachmentsView(attachments: [
            MessageAttachment(name: "Diagram.png", url: nil, imageData: ArtifactPreviewFixtures.imageData),
            MessageAttachment(name: "Notes.txt", url: URL(filePath: "/repo/Notes.txt")),
        ])
        .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
        .frame(width: 360)
        .padding(DS.Space.lg)
    }
}
#endif
