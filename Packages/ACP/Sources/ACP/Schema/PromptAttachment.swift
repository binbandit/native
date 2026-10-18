import Foundation

/// Something sent along with a prompt's text: a file it refers to (an `@` mention or an attached
/// file) or an image.
public enum PromptAttachment: Hashable, Sendable {
    /// Sent as a `resource_link`, which every ACP agent takes, so the agent opens the file itself.
    case file(URL)
    /// Sent only to agents that take images (`AgentCapabilities.image`).
    case image(data: Data, mimeType: String, name: String)

    public var name: String {
        switch self {
        case .file(let url): url.lastPathComponent
        case .image(_, _, let name): name
        }
    }

    public var isImage: Bool {
        if case .image = self { true } else { false }
    }
}

extension ContentBlock {
    /// A prompt's blocks: the text, then each file once, then the images. An agent that doesn't
    /// take images gets a line saying which were left out instead, so neither side is surprised.
    public static func prompt(
        _ text: String, attachments: [PromptAttachment] = [], supportsImages: Bool
    ) -> [ContentBlock] {
        var blocks: [ContentBlock] = text.isEmpty ? [] : [.text(text)]
        var files = Set<URL>()
        var leftOut: [String] = []
        for attachment in attachments {
            switch attachment {
            case .file(let url):
                guard files.insert(url.standardizedFileURL).inserted else { continue }
                blocks.append(.resourceLink(uri: url.absoluteString, name: url.lastPathComponent))
            case .image(let data, let mimeType, let name):
                if supportsImages {
                    blocks.append(.image(data: data.base64EncodedString(), mimeType: mimeType))
                } else {
                    leftOut.append(name)
                }
            }
        }
        if !leftOut.isEmpty {
            blocks.append(
                .text("(Images not sent, since this agent doesn't take images: \(leftOut.joined(separator: ", ")).)"))
        }
        return blocks
    }
}
