import Foundation

/// A file or image that went with a user's message, as the transcript shows it: from what the user
/// attached, or from the blocks an agent replays.
public struct MessageAttachment: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var name: String
    /// Where the file is, when the message said.
    public var url: URL?
    /// The image itself, for an image.
    public var imageData: Data?
    public var embeddedData: Data?
    public var mimeType: String?
    /// The original file's known size, including files sent only as references.
    public var byteCount: Int?
    /// Originally attached by the user; a local task can preview it on the client.
    public var isLocalFile: Bool

    public init(
        name: String, url: URL?, imageData: Data? = nil, embeddedData: Data? = nil, mimeType: String? = nil,
        isLocalFile: Bool = false, byteCount: Int? = nil
    ) {
        self.name = name
        self.url = url
        self.imageData = imageData
        self.embeddedData = embeddedData
        self.mimeType = mimeType
        self.isLocalFile = isLocalFile
        self.byteCount = byteCount
    }

    public var isImage: Bool {
        imageData != nil
    }

    /// What the user attached, as it went to the agent: a picture the agent got as a path shows as
    /// a file, as it will when the session is reloaded. Mentions already show in the text.
    public static func shown(
        _ attachments: [PromptAttachment], capabilities: PromptCapabilities
    ) -> [MessageAttachment] {
        attachments.filter { $0.origin == .attached }.map { attachment in
            let image: Data? =
                switch (attachment.content, attachment.delivery(to: capabilities)) {
                case (.image(let data, _), .image): data
                default: nil
                }
            let embedded: Data? = if case .text(let text) = attachment.content { Data(text.utf8) } else { nil }
            let mimeType: String? = if case .image(_, let mime) = attachment.content { mime } else { nil }
            return MessageAttachment(
                name: attachment.name, url: attachment.url, imageData: image, embeddedData: embedded,
                mimeType: mimeType, isLocalFile: true, byteCount: attachment.byteCount)
        }
    }

    /// A replayed block that stands for an attachment rather than text, including the text forms
    /// agents fold attachments into (`init(replayedText:)`).
    init?(_ block: ContentBlock) {
        switch block {
        case .image(let base64, let mimeType):
            self.init(name: "Image", url: nil, imageData: Data(base64Encoded: base64), mimeType: mimeType)
        case .resourceLink(let uri, let name):
            self.init(name: name, url: URL(string: uri))
        case .resource(let uri, let text, let mimeType):
            let url = URL(string: uri)
            self.init(
                name: url?.lastPathComponent ?? uri, url: url, embeddedData: text.map { Data($0.utf8) },
                mimeType: mimeType)
        case .resourceBlob(let uri, let mimeType, let blob):
            let url = URL(string: uri)
            let data = Data(base64Encoded: blob)
            let isImage = mimeType?.hasPrefix("image/") == true
            self.init(
                name: url?.lastPathComponent ?? "Artifact", url: url, imageData: isImage ? data : nil,
                embeddedData: isImage ? nil : data, mimeType: mimeType)
        case .text(let text):
            self.init(replayedText: text)
        case .unsupported:
            return nil
        }
    }
}
