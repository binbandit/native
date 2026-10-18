import ACP
import Foundation

/// What the composer says when attaching didn't go as planned: an agent that will get a file's
/// path instead of the image, or files that couldn't be attached at all and why.
enum ComposerAttachmentNote {
    /// Said once files are attached, before anything is sent, when the agent can't take an image.
    static func fallback(for added: [PromptAttachment], capabilities: PromptCapabilities, agentName: String) -> String? {
        let linkedImages = added.filter { $0.isImage && $0.delivery(to: capabilities) == .link }
        switch linkedImages.count {
        case 0: return nil
        case 1: return "\(agentName) can’t read images here; it will get the file path instead."
        default: return "\(agentName) can’t read images here; it will get the file paths instead."
        }
    }

    /// The first problem, and how many more there were.
    static func problems(_ messages: [String]) -> String? {
        guard let first = messages.first else { return nil }
        let more = messages.count - 1
        return more == 0 ? "Couldn’t attach: \(first)" : "Couldn’t attach: \(first) (and \(more) more)"
    }
}
