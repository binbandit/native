#if canImport(UniformTypeIdentifiers)
import Foundation
import UniformTypeIdentifiers

/// Distinguishes file-backed documents from ordinary text drags before native text insertion.
public enum TextInputDropProvider {
    public enum Representation: Equatable, Sendable {
        case fileURL
        case image(String)
        case document(String)
    }

    public static func representation(of provider: NSItemProvider) -> Representation? {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return .fileURL }
        if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) {
            return .image(type)
        }
        if let type = provider.registeredTypeIdentifiers(fileOptions: .openInPlace).first {
            return .document(type)
        }
        guard !provider.hasItemConformingToTypeIdentifier(UTType.text.identifier),
            !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
        else { return nil }
        return provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true })
            .map(Representation.document)
    }

    /// Provider URLs expire when their completion returns. The receiver owns this temporary copy
    /// and removes its parent directory after consuming the attachment.
    public static func loadFile(_ provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("NativeTextInput-" + UUID().uuidString, isDirectory: true)
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let copy = directory.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
#endif
