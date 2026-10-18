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

    public init(name: String, url: URL?, imageData: Data? = nil) {
        self.name = name
        self.url = url
        self.imageData = imageData
    }

    public var isImage: Bool {
        imageData != nil
    }

    /// What the user attached; mentions already show in the text.
    public static func shown(_ attachments: [PromptAttachment]) -> [MessageAttachment] {
        attachments.filter { $0.origin == .attached }.map { attachment in
            let image: Data? = if case .image(let data, _) = attachment.content { data } else { nil }
            return MessageAttachment(name: attachment.name, url: attachment.url, imageData: image)
        }
    }

    /// A replayed block that stands for an attachment rather than text.
    init?(_ block: ContentBlock) {
        switch block {
        case .image(let base64, _):
            self.init(name: "Image", url: nil, imageData: Data(base64Encoded: base64))
        case .resourceLink(let uri, let name):
            self.init(name: name, url: URL(string: uri))
        case .resource(let uri, _):
            let url = URL(string: uri)
            self.init(name: url?.lastPathComponent ?? uri, url: url)
        case .text, .unsupported:
            return nil
        }
    }
}
