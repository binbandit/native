import Foundation

/// A private, short-lived copy for system previewers. The caller owns and removes just this directory.
public struct ArtifactPreviewFile: Sendable {
    public static let byteLimit = 50 * 1_000_000
    public let url: URL

    public init(artifact: TranscriptArtifact, data: Data) throws {
        guard data.count <= Self.byteLimit else { throw CocoaError(.fileReadTooLarge) }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Native-Artifact-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent(artifact.filename, isDirectory: false)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        self.url = url
    }

    public func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
