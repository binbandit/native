import ACP
import Foundation

// What goes out with the draft besides its text, and what would stop a message going out at all.
extension SessionModel {
    /// Whether `attachment` can go to this session's agent: images only to agents that take them.
    func canAttach(_ attachment: PromptAttachment) -> Bool {
        !attachment.isImage || supportsImages
    }

    /// Adds a file or image to the draft, once. Returns false for one the agent can't take.
    @discardableResult
    func attach(_ attachment: PromptAttachment) -> Bool {
        guard canAttach(attachment) else { return false }
        if !attachments.contains(attachment) {
            attachments.append(attachment)
        }
        return true
    }

    func removeAttachment(_ attachment: PromptAttachment) {
        attachments.removeAll { $0 == attachment }
    }

    /// Why a message can't go out now, or nil when it can. A session that's loading or busy isn't
    /// blocked: what's sent then waits in the queue.
    var sendBlock: SessionSendBlock? {
        if !acceptsPrompts { return .notAcceptingPrompts }
        if phase == .disconnected { return .disconnected }
        return services.sendGate.block(for: agent)
    }

    /// `sendBlock` in a sentence, for the composer.
    var sendBlockedReason: String? {
        sendBlock?.message
    }
}
