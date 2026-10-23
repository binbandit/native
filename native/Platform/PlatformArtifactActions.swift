import ACP
import Foundation
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// Actions on the client's own artifacts. Host project files are read through RemoteFiles instead.
enum PlatformArtifactActions {
    @concurrent static func readLocal(_ url: URL) async throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard (values.fileSize ?? 0) <= ArtifactPreviewFile.byteLimit else { throw CocoaError(.fileReadTooLarge) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: ArtifactPreviewFile.byteLimit + 1) ?? Data()
        guard data.count <= ArtifactPreviewFile.byteLimit else { throw CocoaError(.fileReadTooLarge) }
        return data
    }

    static func copy(_ data: Data, type: UTType) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        if type.conforms(to: .image), let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        } else if type.conforms(to: .text), let string = String(data: data, encoding: .utf8) {
            pasteboard.setString(string, forType: .string)
        }
        #else
        UIPasteboard.general.setData(data, forPasteboardType: type.identifier)
        #endif
    }
}
