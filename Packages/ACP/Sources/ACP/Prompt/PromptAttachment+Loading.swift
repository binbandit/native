import Foundation
import ImageIO
import UniformTypeIdentifiers

// Reading a file into an attachment: images scaled to what agents take, small text files read for
// embedding, everything else sent by path.
extension PromptAttachment {
    public enum Limits {
        /// The largest image file Native will read and scale down.
        public static let imageFileBytes = 50 * 1_000_000
        /// Images are scaled to fit this many pixels on their long edge.
        public static let imagePixels = 2048
        /// An image's bytes once scaled, so its base64 stays under the 5 MB providers accept.
        public static let imageBytes = 3_750_000
        /// Text files up to this size are embedded for agents that take it; larger ones go by path.
        public static let embeddedTextBytes = 256 * 1024
        /// Files per message.
        public static let count = 20
        /// Bytes per message carried inside the prompt (images and embedded text).
        public static let inlineBytes = 20 * 1_000_000
    }

    public enum LoadError: LocalizedError, Equatable {
        case missing(name: String)
        case unreadable(name: String)
        case imageTooLarge(name: String, byteCount: Int)

        public var errorDescription: String? {
            switch self {
            case .missing(let name): "\(name) isn’t there anymore."
            case .unreadable(let name): "Native couldn’t read \(name)."
            case .imageTooLarge(let name, let byteCount):
                "\(name) is \(Self.size(byteCount)); images can be up to \(Self.size(Limits.imageFileBytes))."
            }
        }

        private static func size(_ bytes: Int) -> String {
            ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
    }

    public enum LimitError: LocalizedError, Equatable {
        case tooMany
        case tooMuchInline(name: String)

        public var errorDescription: String? {
            switch self {
            case .tooMany: "A message can carry up to \(Limits.count) files."
            case .tooMuchInline(let name):
                "\(name) would take this message past \(ByteCountFormatter.string(fromByteCount: Int64(Limits.inlineBytes), countStyle: .file)) of images and files. Send it in the next message."
            }
        }
    }

    /// `existing` with `attachment` added, or as it is when that file is already there. Throws when
    /// the message would pass `Limits`.
    public static func adding(
        _ attachment: PromptAttachment, to existing: [PromptAttachment]
    ) throws -> [PromptAttachment] {
        guard !existing.contains(where: { $0.url.standardizedFileURL == attachment.url.standardizedFileURL }) else {
            return existing
        }
        guard existing.count < Limits.count else { throw LimitError.tooMany }
        let inline = existing.reduce(attachment.inlineByteCount) { $0 + $1.inlineByteCount }
        guard inline <= Limits.inlineBytes else { throw LimitError.tooMuchInline(name: attachment.name) }
        return existing + [attachment]
    }

    /// The image types agents take as they are; anything else is converted.
    static let sendableImageTypes: [UTType] = [.png, .jpeg, .gif, .webP]

    /// Reads `url` into an attachment. Blocks while it reads and scales, so call it off the main
    /// actor.
    public static func load(_ url: URL, origin: Origin = .attached) throws -> PromptAttachment {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey])
        guard let values else { throw LoadError.missing(name: url.lastPathComponent) }
        if values.isDirectory == true || origin == .mentioned {
            return PromptAttachment(url: url, content: .reference, byteCount: values.fileSize, origin: origin)
        }
        let byteCount = values.fileSize ?? 0
        if values.contentType?.conforms(to: .image) == true, let image = try image(at: url, byteCount: byteCount) {
            return PromptAttachment(url: url, content: image, byteCount: byteCount, origin: origin)
        }
        if byteCount <= Limits.embeddedTextBytes {
            guard let data = try? Data(contentsOf: url) else { throw LoadError.unreadable(name: url.lastPathComponent) }
            if let text = String(data: data, encoding: .utf8), !text.contains("\0") {
                return PromptAttachment(url: url, content: .text(text), byteCount: byteCount, origin: origin)
            }
        }
        return PromptAttachment(url: url, content: .reference, byteCount: byteCount, origin: origin)
    }

    /// Saves pasted image data to a file of its own, so it has a path like any attachment, then
    /// loads it.
    public static func pasted(_ data: Data, type: UTType) throws -> PromptAttachment {
        let folder = URL.temporaryDirectory.appending(
            path: "Native Attachments/\(UUID().uuidString)", directoryHint: .isDirectory)
        let url = folder.appending(path: "Pasted Image.\(type.preferredFilenameExtension ?? "png")")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            throw LoadError.unreadable(name: "the pasted image")
        }
        return try load(url)
    }

    /// The image's content: as it is when agents take it as is, otherwise scaled and re-encoded.
    /// Nil when ImageIO can't read it, so it goes as a file.
    private static func image(at url: URL, byteCount: Int) throws -> Content? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        guard byteCount <= Limits.imageFileBytes else {
            throw LoadError.imageTooLarge(name: url.lastPathComponent, byteCount: byteCount)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = properties?[kCGImagePropertyOrientation] as? Int ?? 1
        let type = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
        if let type, let mimeType = type.preferredMIMEType, sendableImageTypes.contains(type), orientation == 1,
            max(width, height) <= Limits.imagePixels, byteCount <= Limits.imageBytes,
            let data = try? Data(contentsOf: url)
        {
            return .image(data, mimeType: mimeType)
        }
        guard let scaled = scaled(source) else { throw LoadError.unreadable(name: url.lastPathComponent) }
        return encoded(scaled).map { .image($0.data, mimeType: $0.mimeType) }
    }

    /// The image upright and fitting `Limits.imagePixels`.
    private static func scaled(_ source: CGImageSource) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Limits.imagePixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// PNG while it fits `Limits.imageBytes` (screenshots stay sharp), else JPEG on white.
    private static func encoded(_ image: CGImage) -> (data: Data, mimeType: String)? {
        if let png = encode(image, as: .png), png.count <= Limits.imageBytes {
            return (png, "image/png")
        }
        for quality in [0.85, 0.7, 0.5] {
            if let jpeg = encode(flattened(image) ?? image, as: .jpeg, quality: quality),
                jpeg.count <= Limits.imageBytes
            {
                return (jpeg, "image/jpeg")
            }
        }
        return nil
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// The image over white, so transparent parts don't turn black in a JPEG.
    private static func flattened(_ image: CGImage) -> CGImage? {
        guard
            let context = CGContext(
                data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }
}
