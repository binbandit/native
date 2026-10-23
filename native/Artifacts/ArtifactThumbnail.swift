import ACP
import SwiftUI

/// A quiet transcript entry shared by attached files, agent replies and tool results.
struct ArtifactThumbnail: View {
    let artifact: TranscriptArtifact
    @Environment(\.openTranscriptArtifact) private var openArtifact

    var body: some View {
        Button {
            openArtifact?(artifact)
        } label: {
            if artifact.isImage, let data = artifact.data, ImageHeader(data) != nil {
                AttachmentImage(
                    data: data, maxSide: DS.Artifact.thumbnailWidth,
                    fitting: CGSize(width: DS.Artifact.thumbnailWidth, height: DS.Artifact.thumbnailHeight)
                )
                .clipShape(.rect(cornerRadius: DS.Radius.card))
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(.dsBorder)
                }
                .contentShape(.rect)
            } else {
                Label(artifact.name, systemImage: artifact.isImage ? "photo" : "doc")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
                    .frame(minHeight: DS.Size.minimumHitTarget)
                    .background(.dsFill, in: .rect(cornerRadius: DS.Radius.control))
                    .contentShape(.rect)
            }
        }
        .buttonStyle(.plain)
        .disabled(openArtifact == nil)
        .help("Open \(artifact.name)")
        .accessibilityLabel("Open \(artifact.name)")
        .accessibilityHint("Opens the artifact viewer")
        .contextMenu {
            Button("Open", systemImage: "eye") { openArtifact?(artifact) }
        }
    }
}

extension EnvironmentValues {
    @Entry var openTranscriptArtifact: ((TranscriptArtifact) -> Void)?
}

#if DEBUG
#Preview("Transcript artifacts - Image, file and unavailable image") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ArtifactThumbnail(
                artifact: TranscriptArtifact(name: "Diagram.png", data: ArtifactPreviewFixtures.imageData))
            ArtifactThumbnail(artifact: TranscriptArtifact(name: "Report.pdf", url: URL(filePath: "/report.pdf")))
            ArtifactThumbnail(artifact: TranscriptArtifact(name: "Image", mimeType: "image/png"))
        }
        .environment(\.openTranscriptArtifact, { _ in })
        .padding(DS.Space.lg)
    }
}
#endif
