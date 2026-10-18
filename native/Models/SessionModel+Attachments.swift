import ACP
import Foundation

// What goes out with the draft besides its text, and what would stop a message going out at all.
extension SessionModel {
    /// Adds a file or image to the draft; a file already attached is left as it is. Throws when the
    /// message would pass `PromptAttachment.Limits`.
    func attach(_ attachment: PromptAttachment) throws {
        attachments = try PromptAttachment.adding(attachment, to: attachments)
    }

    func removeAttachment(_ id: PromptAttachment.ID) {
        attachments.removeAll { $0.id == id }
    }

    /// Why a message can't go out now, or nil when it can. A session that's loading or busy isn't
    /// blocked: what's sent then waits in the queue.
    var sendBlock: SessionSendBlock? {
        if !acceptsPrompts { return .notAcceptingPrompts }
        if phase == .disconnected { return .disconnected(agentName: agentName) }
        return services.sendGate.block(for: agent)
    }

    /// `sendBlock` in a sentence, for the composer.
    var sendBlockedReason: String? {
        sendBlock?.message
    }
}
