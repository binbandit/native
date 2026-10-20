import Foundation

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// A file or image sent along with a prompt's text: one the user attached, or one an `@` mention in
/// the text names. Every attachment is a file on disk (a pasted image is saved to one first), so an
/// agent that can't take its contents still gets its path.
public struct PromptAttachment: Identifiable, Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        /// An image, already within what agents take (`PromptAttachment.Limits`).
        case image(Data, mimeType: String)
        /// A small text file's contents, embedded for agents that take embedded context.
        case text(String)
        /// Only where the file is: a folder, a large or binary file, or a mention.
        case reference
    }

    public enum Origin: Hashable, Sendable {
        /// Attached by the user, and shown with the message.
        case attached
        /// Named by an `@` mention in the text, which already shows it.
        case mentioned
    }

    /// How an attachment reaches an agent, by what the agent takes.
    public enum Delivery: Hashable, Sendable {
        case image
        case embedded
        case link
    }

    public let id: UUID
    public let url: URL
    public let content: Content
    /// The file's size on disk; nil for a folder.
    public let byteCount: Int?
    public let origin: Origin

    public init(url: URL, content: Content, byteCount: Int?, origin: Origin = .attached) {
        id = UUID()
        self.url = url
        self.content = content
        self.byteCount = byteCount
        self.origin = origin
    }

    public var name: String {
        url.lastPathComponent
    }

    public var isImage: Bool {
        if case .image = content { true } else { false }
    }

    /// Whether the file is a picture, whether or not it goes as one: one too large to send, or one
    /// ImageIO can't draw, goes by its path.
    public var isImageFile: Bool {
        #if canImport(UniformTypeIdentifiers)
        isImage || UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        #else
        isImage || Self.isPicture(extension: url.pathExtension)
        #endif
    }

    /// The bytes that travel inside the prompt rather than as a path.
    public var inlineByteCount: Int {
        switch content {
        case .image(let data, _): data.count
        case .text(let text): text.utf8.count
        case .reference: 0
        }
    }

    public func delivery(to capabilities: PromptCapabilities) -> Delivery {
        switch content {
        case .image where capabilities.image: .image
        case .text where capabilities.embeddedContext: .embedded
        case .image, .text, .reference: .link
        }
    }
}

extension ContentBlock {
    /// A prompt's blocks: the text, then each file once, as the agent takes it: an image, its
    /// contents embedded, or a `resource_link` to its path, which every agent takes.
    public static func prompt(
        _ text: String, attachments: [PromptAttachment] = [], capabilities: PromptCapabilities
    ) -> [ContentBlock] {
        var blocks: [ContentBlock] = text.isEmpty ? [] : [.text(text)]
        var seen = Set<URL>()
        for attachment in attachments where seen.insert(attachment.url.standardizedFileURL).inserted {
            let uri = attachment.url.absoluteString
            switch (attachment.delivery(to: capabilities), attachment.content) {
            case (.image, .image(let data, let mimeType)):
                blocks.append(.image(data: data.base64EncodedString(), mimeType: mimeType))
            case (.embedded, .text(let contents)):
                blocks.append(.resource(uri: uri, text: contents))
            default:
                blocks.append(.resourceLink(uri: uri, name: attachment.name))
            }
        }
        return blocks
    }
}
