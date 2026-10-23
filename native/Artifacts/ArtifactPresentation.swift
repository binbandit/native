import ACP
import SwiftUI

struct ArtifactPresentation: ViewModifier {
    let session: SessionModel
    let filesAreLocal: Bool

    func body(content: Content) -> some View {
        content
            .environment(
                \.openTranscriptArtifact, TranscriptArtifactOpener(session: session, filesAreLocal: filesAreLocal)
            )
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard url.isFileURL || (url.scheme == nil && !url.relativeString.hasPrefix("#")) else {
                        return .systemAction
                    }
                    session.openArtifact(
                        TranscriptArtifact(name: url.lastPathComponent, url: url), filesAreLocal: filesAreLocal)
                    return .handled
                }
            )
            .sheet(
                isPresented: Binding(
                    get: { session.artifactViewer.isPresented },
                    set: { if !$0 { session.artifactViewer.close() } }
                )
            ) {
                ArtifactViewer(model: session.artifactViewer)
                    .presentationSizing(.fitted)
            }
            .onDisappear { session.artifactViewer.close() }
    }
}

#if DEBUG
#Preview("Artifact presentation - Open from transcript") {
    let app = AppModel.preview(.empty)
    let task = SessionModel.preview(in: app)
    return DSPreviewPair {
        if let task {
            ArtifactThumbnail(
                artifact: TranscriptArtifact(name: "Diagram.png", data: ArtifactPreviewFixtures.imageData)
            )
            .modifier(ArtifactPresentation(session: task, filesAreLocal: true))
            .padding(DS.Space.xl)
        }
    }
}
#endif
