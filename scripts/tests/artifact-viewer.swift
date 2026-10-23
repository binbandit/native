import ACP
import SwiftUI
import UniformTypeIdentifiers

@testable import Native

@main
@MainActor
private struct ArtifactViewerRegression {
    private static var failures = 0

    static func main() async throws {
        let bytes = ArtifactPreviewFixtures.imageData
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("diagram.png")
        try bytes.write(to: original)
        var copied: Data?
        var revealed: URL?
        let model = ArtifactViewerModel(copy: { data, _ in copied = data }, reveal: { revealed = $0 })
        model.open(TranscriptArtifact(name: "diagram.png", url: original, data: bytes), localFiles: true) { _ in
            throw CocoaError(.fileReadNoSuchFile)
        }
        await loaded(model)
        expect(model.image != nil, "Embedded image opens without reading its original")
        model.resize(CGSize(width: 600, height: 400))
        model.zoom(by: 2)
        expect(model.viewport.zoom == 2, "Zoom changes through the model")
        model.fit()
        expect(model.viewport.zoom == 1, "Fit resets zoom")
        model.copy()
        expect(copied == bytes && model.feedback == "Copied", "Copy sends the original image to the fake pasteboard")
        for _ in 0..<100 where model.revealURL == nil { try await Task.sleep(for: .milliseconds(10)) }
        model.reveal()
        expect(revealed == original, "Reveal sends only the on-disk original to the fake Finder")
        model.saveAs()
        expect(model.isExporting, "Save As opens the export state")
        let exported = directory.appendingPathComponent("saved.png")
        try FileWrapper(regularFileWithContents: try require(model.data)).write(
            to: exported, options: .atomic, originalContentsURL: nil)
        model.exported(.success(exported))
        expect(try Data(contentsOf: exported) == bytes, "Saved bytes match the original")
        expect(model.feedback == "Saved", "Export reports success")
        model.reveal()
        expect(revealed == exported, "After Save As, reveal opens the saved copy")
        model.close()
        expect(!model.isPresented && model.data == nil && model.image == nil, "Close releases image bytes")

        let folder = directory.appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        revealed = nil
        model.open(TranscriptArtifact(name: "Attachments", url: folder), localFiles: true) { _ in
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        expect(revealed == folder && !model.isPresented, "Folders keep their existing file-browser action")
        model.close()

        model.open(TranscriptArtifact(name: "notes.txt", data: Data("Notes".utf8)), localFiles: false) { _ in Data() }
        await loaded(model)
        let preview = try require(model.previewFile?.url)
        expect(try String(contentsOf: preview, encoding: .utf8) == "Notes", "Non-image preview contains the artifact")
        expect(model.revealURL == nil, "Remote and embedded artifacts never reveal a local path")
        model.close()
        expect(!FileManager.default.fileExists(atPath: preview.path), "Close deletes the private preview file")

        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>"
        let svgArtifact = try require(
            TranscriptArtifact(.resource(uri: "artifact:///diagram", text: svg, mimeType: "image/svg+xml")))
        model.open(svgArtifact, localFiles: false) { _ in throw CocoaError(.fileReadNoSuchFile) }
        await loaded(model)
        let svgPreview = try require(model.previewFile?.url)
        expect(model.error == nil && svgPreview.pathExtension == "svg", "Text-backed SVG uses a native image preview")
        expect(
            try String(contentsOf: svgPreview, encoding: .utf8) == svg, "SVG preview preserves its supplied contents")
        model.close()

        model.open(TranscriptArtifact(name: "missing.png", url: original), localFiles: false) { _ in
            throw CocoaError(.fileReadNoSuchFile)
        }
        await loaded(model)
        expect(model.error != nil && model.isPresented, "Unreadable file leaves a closable error")
        expect(model.canRetry, "A file read can be retried after its file or host recovers")
        model.close()
        model.open(
            TranscriptArtifact(name: "bad.png", data: Data([1, 2, 3]), mimeType: "image/png"), localFiles: false
        ) { _ in Data() }
        await loaded(model)
        expect(model.error != nil && model.data != nil, "Corrupt image offers recovery while retaining export bytes")
        expect(!model.canRetry, "Fixed embedded bytes do not offer an ineffective retry")
        model.close()

        model.open(TranscriptArtifact(name: "slow.txt", url: original), localFiles: false) { _ in
            try? await Task.sleep(for: .milliseconds(50))
            return Data("Late".utf8)
        }
        model.close()
        try await Task.sleep(for: .milliseconds(100))
        expect(model.artifact == nil && model.previewFile == nil, "A cancelled read cannot reopen the viewer")
        if failures > 0 { exit(1) }
        print("PASS: image open, zoom, fit, copy, export, reveal, file preview, errors, cleanup and cancellation")
    }

    private static func loaded(_ model: ArtifactViewerModel) async {
        for _ in 0..<200 where model.isLoading { try? await Task.sleep(for: .milliseconds(10)) }
        expect(!model.isLoading, "Loading completes")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }

    private static func expect(_ condition: Bool, _ message: String) {
        if !condition { print("FAIL: \(message)"); failures += 1 }
    }
}
