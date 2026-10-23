import Foundation

#if canImport(ImageIO)
import ImageIO
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A transcript artifact's supplied bytes and optional origin. Opening never implies downloading a URL.
public struct TranscriptArtifact: Hashable, Sendable {
    public var name: String
    public var url: URL?
    public var data: Data?
    public var mimeType: String?
    public var isLocalFile: Bool

    public init(name: String, url: URL? = nil, data: Data? = nil, mimeType: String? = nil, isLocalFile: Bool = false) {
        self.name = name
        self.url = url
        self.data = data
        self.mimeType = mimeType
        self.isLocalFile = isLocalFile
    }

    public init(_ attachment: MessageAttachment) {
        self.init(
            name: attachment.name, url: attachment.url, data: attachment.imageData ?? attachment.embeddedData,
            mimeType: attachment.mimeType, isLocalFile: attachment.isLocalFile)
    }

    public init?(_ block: ContentBlock) {
        switch block {
        case .image(let base64, let mimeType):
            self.init(name: "Image", data: Data(base64Encoded: base64), mimeType: mimeType)
        case .resourceLink(let uri, let name):
            self.init(
                name: name.isEmpty ? URL(string: uri)?.lastPathComponent ?? "Artifact" : name, url: URL(string: uri))
        case .resource(let uri, let text, let mimeType):
            self.init(
                name: URL(string: uri)?.lastPathComponent ?? "Artifact", url: URL(string: uri),
                data: text.map { Data($0.utf8) }, mimeType: mimeType)
        case .resourceBlob(let uri, let mimeType, let blob):
            self.init(
                name: URL(string: uri)?.lastPathComponent ?? "Artifact", url: URL(string: uri),
                data: Data(base64Encoded: blob), mimeType: mimeType)
        default:
            return nil
        }
    }

    public var isImage: Bool {
        if mimeType?.hasPrefix("image/") == true { return true }
        if hasImageHeader { return true }
        #if canImport(UniformTypeIdentifiers)
        return UTType(filenameExtension: url?.pathExtension ?? (name as NSString).pathExtension)?.conforms(to: .image)
            == true
        #else
        return ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg"].contains(
            url?.pathExtension.lowercased() ?? (name as NSString).pathExtension.lowercased())
        #endif
    }

    public var isFolder: Bool { url?.hasDirectoryPath == true || name.hasSuffix("/") }

    /// Check the platform's supported headers without decoding full-sized pixels on the UI thread.
    public var hasImageHeader: Bool {
        guard let data else { return false }
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
        #else
        return ImageHeader(data) != nil
        #endif
    }

    /// Agent-provided names may contain paths. Temporary previews and exports use one filename only.
    public var filename: String {
        let leaf = (name.replacingOccurrences(of: "\\", with: "/") as NSString).lastPathComponent
        let clean = leaf.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        var result = String(String.UnicodeScalarView(clean))
        if result.isEmpty || result == "." || result == ".." { result = "Artifact" }
        let detected = data.flatMap(ImageHeader.init)?.mimeType ?? mimeType
        #if canImport(UniformTypeIdentifiers)
        if let detected, let type = UTType(mimeType: detected), let suffix = type.preferredFilenameExtension {
            let current = UTType(filenameExtension: (result as NSString).pathExtension)
            if current != type { result += "." + suffix }
        } else if data != nil, (result as NSString).pathExtension.isEmpty, !isImage {
            result += ".txt"
        }
        #else
        if (result as NSString).pathExtension.isEmpty {
            let suffix = [
                "image/png": "png", "image/jpeg": "jpg", "image/gif": "gif", "image/webp": "webp",
                "image/heic": "heic", "image/tiff": "tiff", "image/svg+xml": "svg",
                "application/pdf": "pdf", "text/plain": "txt", "text/html": "html",
            ][detected ?? ""]
            if let suffix { result += "." + suffix } else if data != nil, !isImage { result += ".txt" }
        }
        #endif
        return String(result.prefix(180))
    }
}
