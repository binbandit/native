import ACP
import SwiftUI
import UniformTypeIdentifiers

/// What can be dropped on the composer or the transcript: files (and links), or image data from an
/// app that drags pictures rather than files.
enum ComposerDropItem: Transferable {
    case file(URL)
    case image(Data, UTType)

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
