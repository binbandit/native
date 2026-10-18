import ACP
import Foundation

/// What the composer says once files are attached, before anything is sent: what it couldn't take
/// and why, or which pictures the agent will get as a path instead of an image.
enum ComposerAttachmentNote {
    /// The note for one round of attaching: `added` made it, `refused` didn't fit the message's
    /// file limit, and `problems` couldn't be read.
    static func feedback(
        added: [PromptAttachment], refused: Int, problems: [any Error], capabilities: PromptCapabilities,
        agentName: String
    ) -> ComposerFeedback? {
        if let problem = problem(problems) {
            return ComposerFeedback(tone: .problem, message: problem)
        }
        if refused > 0 {
            return ComposerFeedback(tone: .problem, message: tooMany(added: added.count, refused: refused))
        }
        return pathOnly(added, capabilities: capabilities, agentName: agentName).map {
            ComposerFeedback(tone: .notice, message: $0)
        }
    }

    /// Why a picture goes as its path, for its chip and the note; nil when it goes as an image.
    static func pathOnlyReason(
        for attachment: PromptAttachment, capabilities: PromptCapabilities, agentName: String
    ) -> String? {
        guard attachment.isImageFile, attachment.delivery(to: capabilities) == .link else { return nil }
        if !capabilities.image {
            return "\(agentName) can’t take images, so it gets the file’s path instead."
        }
        if let bytes = attachment.byteCount, bytes > PromptAttachment.Limits.imageFileBytes {
            return "It’s over the \(DSFormat.fileSize(PromptAttachment.Limits.imageFileBytes)) Native sends as an "
                + "image, so \(agentName) gets its path instead."
        }
        return "Native couldn’t read it as an image, so \(agentName) gets its path instead."
    }

    private static func pathOnly(
        _ added: [PromptAttachment], capabilities: PromptCapabilities, agentName: String
    ) -> String? {
        let linked = added.filter { pathOnlyReason(for: $0, capabilities: capabilities, agentName: agentName) != nil }
        guard let first = linked.first else { return nil }
        if !capabilities.image {
            let what = linked.count == 1 ? "\(first.name)’s path" : "the paths of \(linked.count) images"
            return "\(agentName) can’t take images, so it gets \(what) instead."
        }
        let reason = pathOnlyReason(for: first, capabilities: capabilities, agentName: agentName) ?? ""
        return "\(first.name): \(reason)"
    }

    /// "Attached 20 of 30 files: …", or, when the message was already full, that it is.
    private static func tooMany(added: Int, refused: Int) -> String {
        let limit = PromptAttachment.Limits.count
        if added == 0 {
            return "This message already carries \(limit) files, the most it can. Send it, then attach the rest."
        }
        return "Attached \(added) of \(added + refused) files: a message can carry up to \(limit). "
            + "Send these, then attach the rest."
    }

    /// The first problem, and how many more there were.
    private static func problem(_ errors: [any Error]) -> String? {
        guard let first = errors.first?.localizedDescription else { return nil }
        let more = errors.count - 1
        return more == 0 ? "Couldn’t attach: \(first)" : "Couldn’t attach: \(first) \(more) more couldn’t either."
    }
}
