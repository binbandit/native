import ACP
import Foundation

// What goes out with the draft besides its text, and what would stop a message going out at all.
extension SessionModel {
    /// Adds a file or image to the draft; a file already attached is left as it is. Throws when the
    /// message would pass `PromptAttachment.Limits`.
    func attach(_ attachment: PromptAttachment) throws {
        attachments = try PromptAttachment.adding(attachment, to: attachments)
    }

    /// Takes a file off the draft; with an undo manager, ⌘Z puts it back in its place.
    func removeAttachment(_ id: PromptAttachment.ID, undoManager: UndoManager? = nil) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        let removed = attachments.remove(at: index)
        undoManager?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                guard !session.attachments.contains(where: { $0.id == removed.id }) else { return }
                session.attachments.insert(removed, at: min(index, session.attachments.count))
            }
        }
        undoManager?.setActionName("Remove Attachment")
    }

    /// Attached files that are gone from disk and would reach the agent only as their path, which
    /// leads nowhere now. An image or text file whose contents go with the message still can.
    var missingAttachments: [PromptAttachment] {
        attachments.filter { attachment in
            attachment.delivery(to: promptCapabilities) == .link
                && !FileManager.default.fileExists(atPath: attachment.url.path(percentEncoded: false))
        }
    }

    /// Why a message can't go out now, or nil when it can. A session that's loading or busy isn't
    /// blocked: what's sent then waits in the queue.
    var sendBlock: SessionSendBlock? {
        if !acceptsPrompts { return isEarlierConversation ? .earlierConversation : .notAcceptingPrompts }
        if phase == .disconnected { return .disconnected(agentName: agentName) }
        return services.sendGate.block(for: agent)
    }

    /// `sendBlock` in a sentence, for the composer.
    var sendBlockedReason: String? {
        sendBlock?.message
    }
}
