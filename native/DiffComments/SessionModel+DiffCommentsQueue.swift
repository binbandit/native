import ACP
import NativeHostProtocol

extension SessionModel {
    func isEditingDiffCommentPacket(_ id: QueuedPrompt.ID) -> Bool {
        !diffComments.isEmpty
            || queuedPrompts.first(where: { $0.id == id }).map {
                PromptQuote.split($0.text).quotes.contains { $0.comment != nil }
            } == true
    }

    /// An edited packet remains in the composer until the queue owner acknowledges the update.
    @discardableResult
    func saveQueuedDiffComments(_ id: QueuedPrompt.ID) async -> Bool {
        guard !diffCommentSending, unresolvedCommentPacket == nil,
            prepareDiffCommentsSubmission(), diffCommentSendBlock == nil
        else { return false }
        guard queuedPrompts.contains(where: { $0.id == id }) else {
            diffCommentStatus = "The queued message has already left. Your edited comments are kept."
            return false
        }
        let packet = PromptQuote.trimmed(draft)
        guard !packet.isEmpty else { return false }
        diffCommentSending = true
        unresolvedCommentPacket = packet
        diffCommentStatus = "Checking whether your comments arrived…"
        defer {
            diffCommentSending = false
            reconcileDiffCommentDelivery()
        }
        do {
            if let index = heldPrompts.firstIndex(where: { $0.id == id }) {
                heldPrompts[index].text = packet
            } else if let host {
                let params = QueueItemParams(sessionID: host.id, itemID: id, text: packet)
                try await host.request { try await $0.updateQueued(params) }
            } else {
                queue.update(id, text: packet)
            }
            acceptDiffCommentPacket(packet)
            return true
        } catch {
            if error is RPCError || error is SendError {
                unresolvedCommentPacket = nil
                diffCommentStatus = "Couldn’t save the queued message. Your comments are kept."
            } else {
                diffCommentStatus = "Delivery is unresolved. Your comments are kept. Resending may send duplicates."
            }
            return false
        }
    }
}
