import ACP
import CoreGraphics
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// One task's transient viewer. All open, navigation and file actions pass through this model.
@Observable
final class ArtifactViewerModel {
    typealias Reader = @Sendable (URL) async throws -> Data

    private(set) var artifact: TranscriptArtifact?
    private(set) var data: Data?
    private(set) var image: CGImage?
    private(set) var previewFile: ArtifactPreviewFile?
    private(set) var viewport = ArtifactViewport()
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var feedback: String?
    private(set) var revealURL: URL?
    var isExporting = false

    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var reader: Reader?
    @ObservationIgnored private var canRevealFiles = false
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private let copyData: @MainActor (Data, UTType) -> Void
    @ObservationIgnored private let revealFile: @MainActor (URL) -> Void

    init(
        copy: @escaping @MainActor (Data, UTType) -> Void = PlatformArtifactActions.copy,
        reveal: @escaping @MainActor (URL) -> Void = PlatformFileBrowser.reveal
    ) {
        copyData = copy
        revealFile = reveal
    }

    var isPresented: Bool { artifact != nil }
    var canRetry: Bool { artifact?.data == nil && artifact?.url?.isFileURL == true }
    var contentType: UTType {
        if let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source) as String?
        {
            return UTType(identifier) ?? .data
        }
        return artifact?.mimeType.flatMap { UTType(mimeType: $0) }
            ?? artifact.flatMap { UTType(filenameExtension: ($0.filename as NSString).pathExtension) } ?? .data
    }

    func open(_ artifact: TranscriptArtifact, localFiles: Bool, reader: @escaping Reader) {
        close()
        self.artifact = artifact
        self.reader = reader
        canRevealFiles = localFiles && PlatformFileBrowser.canReveal
        load()
    }

    func retry() { load() }

    private func load() {
        guard let artifact, let reader else { return }
        loading?.cancel()
        let request = UUID()
        requestID = request
        isLoading = true
        error = nil
        let canRevealFiles = canRevealFiles
        loading = Task { [weak self] in
            do {
                let bytes: Data
                if let embedded = artifact.data {
                    bytes = embedded
                } else if let url = artifact.url, url.isFileURL {
                    bytes = try await reader(url)
                } else {
                    throw ArtifactViewerFailure.noData
                }
                guard bytes.count <= ArtifactPreviewFile.byteLimit else { throw CocoaError(.fileReadTooLarge) }
                let prepared = try await Self.prepare(artifact, data: bytes)
                guard !Task.isCancelled, let self, self.requestID == request else {
                    prepared.file?.remove()
                    return
                }
                self.data = bytes
                self.image = prepared.image
                self.previewFile?.remove()
                self.previewFile = prepared.file
                let usesNativePreview =
                    artifact.mimeType == "image/svg+xml" || artifact.filename.lowercased().hasSuffix(".svg")
                self.error =
                    prepared.image == nil && artifact.isImage && !usesNativePreview
                    ? "The image data couldn't be decoded. You can save a copy or close the viewer." : nil
                self.isLoading = false
            } catch {
                guard !Task.isCancelled, let self, self.requestID == request else { return }
                if error is ArtifactViewerFailure {
                    self.error =
                        artifact.url == nil
                        ? "The image data is missing or invalid. Ask the agent to attach the image again."
                        : "This artifact has a link but no preview data. Ask the agent to attach the file."
                } else {
                    self.error =
                        "The file is missing, too large, or can't be read. Check the file and its host, then try again."
                }
                self.isLoading = false
            }
            // A disconnected volume must not delay an image whose bytes are already in the task.
            let original = canRevealFiles ? await PlatformArtifactActions.existingFile(artifact.url) : nil
            guard !Task.isCancelled, self?.requestID == request else { return }
            self?.revealURL = original
        }
    }

    func close() {
        requestID = UUID()
        loading?.cancel()
        loading = nil
        previewFile?.remove()
        previewFile = nil
        artifact = nil
        data = nil
        image = nil
        revealURL = nil
        error = nil
        feedback = nil
        reader = nil
        isLoading = false
        isExporting = false
        viewport = ArtifactViewport()
    }

    func resize(_ size: CGSize) {
        guard let image else { return }
        viewport.resize(image: CGSize(width: image.width, height: image.height), container: size)
    }

    func zoom(by factor: Double) { viewport.setZoom(viewport.zoom * factor) }
    func setZoom(_ value: Double, anchor: CGPoint = .zero) { viewport.setZoom(value, anchor: anchor) }
    func toggleZoom() { viewport.zoom > 1 ? fit() : zoom(by: 2) }
    func pan(by translation: CGSize) { viewport.pan(by: translation) }
    func fit() { viewport.fit() }

    func copy() {
        guard let data else { return }
        copyData(data, contentType)
        feedback = "Copied"
    }

    func saveAs() {
        guard data != nil else { return }
        isExporting = true
    }

    func exported(_ result: Result<URL, any Error>) {
        switch result {
        case .success: feedback = "Saved"
        case .failure: feedback = "Couldn't save the file. Try Save As again."
        }
    }

    func reveal() {
        guard let revealURL else { return }
        revealFile(revealURL)
    }

    @concurrent private static func prepare(
        _ artifact: TranscriptArtifact, data: Data
    ) async throws -> (image: CGImage?, file: ArtifactPreviewFile?) {
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            // Bound decoded memory even for a very large compressed image. Export keeps the original bytes.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 8192,
            ]
            if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return (image, nil)
            }
        }
        return (nil, try ArtifactPreviewFile(artifact: artifact, data: data))
    }

    private enum ArtifactViewerFailure: Error { case noData }

    #if DEBUG
    static func preview(data: Data? = nil, loading: Bool = false, error: String? = nil) -> ArtifactViewerModel {
        let model = ArtifactViewerModel()
        model.artifact = TranscriptArtifact(name: "Diagram.png", data: data, mimeType: "image/png")
        model.data = data
        if let data, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            model.image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        model.isLoading = loading
        model.error = error
        return model
    }
    #endif
}
