import ACP
import Foundation
import NativeHostClient

extension SessionModel {
    func openArtifact(_ artifact: TranscriptArtifact, filesAreLocal: Bool) {
        let client = host?.client
        var resolved = artifact
        if let url = resolved.url, url.scheme == nil {
            resolved.url = URL(filePath: url.path(percentEncoded: false), relativeTo: cwd)
        }
        artifactViewer.open(resolved, localFiles: filesAreLocal) { url in
            if filesAreLocal && (artifact.isLocalFile || client == nil) {
                return try await PlatformArtifactActions.readLocal(url)
            }
            guard let client else { throw CocoaError(.fileReadNoPermission) }
            return try await RemoteFiles(client: client).data(
                at: url.path(percentEncoded: false), limit: ArtifactPreviewFile.byteLimit)
        }
    }
}
