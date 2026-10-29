import ACP
import SwiftUI
import UniformTypeIdentifiers

/// What can be dropped on the composer or the transcript: files (and links), or image data from an
/// app that drags pictures rather than files.
enum ComposerDropItem: Transferable {
    case file(URL)
    case image(Data, UTType)
    case failed(String)

    /// Copied documents can offer only a typed file representation, without a file URL. Text
    /// selections, including those carrying a link or picture, keep the editor's normal paste.
    nonisolated static func acceptsPaste(_ provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            || provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier)
            || !provider.registeredTypeIdentifiers(fileOptions: .openInPlace).isEmpty
        {
            return true
        }
        return !provider.hasItemConformingToTypeIdentifier(UTType.text.identifier)
            && !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            && (provider.hasItemConformingToTypeIdentifier(UTType.image.identifier)
                || provider.hasItemConformingToTypeIdentifier(UTType.data.identifier))
    }

    nonisolated static func load(_ provider: NSItemProvider) async throws -> ComposerDropItem {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadTransferable(type: Self.self) { continuation.resume(with: $0) }
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .fileURL) { data in
            guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ComposerDropItem.file(url)
        }
        ProxyRepresentation(importing: { (url: URL) in ComposerDropItem.file(url) })
        DataRepresentation(importedContentType: .png) { ComposerDropItem.image($0, .png) }
        DataRepresentation(importedContentType: .jpeg) { ComposerDropItem.image($0, .jpeg) }
        DataRepresentation(importedContentType: .tiff) { ComposerDropItem.image($0, .tiff) }
        DataRepresentation(importedContentType: .heic) { ComposerDropItem.image($0, .heic) }
        DataRepresentation(importedContentType: .gif) { ComposerDropItem.image($0, .gif) }
        DataRepresentation(importedContentType: .webP) { ComposerDropItem.image($0, .webP) }
        DataRepresentation(importedContentType: .image) { ComposerDropItem.image($0, .image) }
        FileRepresentation(importedContentType: .item) { received in
            try await importFile(received.file)
        }
    }

    @concurrent
    private nonisolated static func importFile(_ url: URL) async throws -> ComposerDropItem {
        .file(try PromptAttachment.importFile(url))
    }
}
