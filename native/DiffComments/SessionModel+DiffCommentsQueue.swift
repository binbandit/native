import ACP
import NativeHostClient
import NativeHostProtocol

extension SessionModel {
    var isEditingPendingLocalDiffComments: Bool {
        editingQueuedPrompt.map(ownsPendingLocalDiffComments) == true
    }

    private func ownsPendingLocalDiffComments(_ id: QueuedPrompt.ID) -> Bool {
        guard host == nil || heldPrompts.contains(where: { $0.id == id }),
            let pending = unresolvedCommentPacket, let item = queuedPrompts.first(where: { $0.id == id })
        else { return false }
        return PromptQuote.trimmed(pending) == PromptQuote.trimmed(item.text)
    }

    func isEditingDiffCommentPacket(_ id: QueuedPrompt.ID) -> Bool {
        !diffComments.isEmpty
            || queuedPrompts.first(where: { $0.id == id }).map {
                PromptQuote.split($0.text).quotes.contains { $0.comment != nil }
            } == true
    }

    /// An edited packet remains in the composer until the queue owner acknowledges the update.
    @discardableResult
    func saveQueuedDiffComments(_ id: QueuedPrompt.ID) async -> Bool {
        let isLocal = host == nil || heldPrompts.contains(where: { $0.id == id })
        guard acceptsPrompts, !diffCommentSending, unresolvedCommentPacket == nil || ownsPendingLocalDiffComments(id),
            prepareDiffCommentsSubmission(), sourceExcerptBlock(for: draft) == nil
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
            if isLocal {
                keepLocallyQueuedDiffComments(packet)
                editingQueuedPrompt = nil
            } else {
                // Older hosts return an empty success even when the item has already drained.
                // The owner's published packet, or its transcript receipt, establishes storage.
                for _ in 0..<100 {
                    reconcileDiffCommentDelivery(whileSending: true)
                    if unresolvedCommentPacket == nil { return true }
                    try await Task.sleep(for: .milliseconds(20))
                }
                diffCommentStatus = "Delivery is unresolved. Your comments are kept. Resending may send duplicates."
                return false
            }
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

    var hasLocallyQueuedDiffComments: Bool {
        guard let packet = unresolvedCommentPacket else { return false }
        return heldPrompts.contains { $0.text == packet }
            || (host == nil && queue.visible.contains { $0.text == packet })
    }

    func keepLocallyQueuedDiffComments(_ packet: String) {
        unresolvedCommentPacket = packet
        diffCommentStatus = "Your comments are kept while this task waits to send them."
    }

    func finishHeldDiffComments(_ text: String, attachments files: [PromptAttachment], error: Error? = nil) {
        if error == nil, PromptQuote.split(text).quotes.contains(where: { $0.comment != nil }) {
            attachments.removeAll { files.contains($0) }
        }
        guard let pending = unresolvedCommentPacket, PromptQuote.trimmed(text) == PromptQuote.trimmed(pending) else {
            return
        }
        if let error {
            if error is RPCError || error is SendError {
                unresolvedCommentPacket = nil
                diffCommentStatus = "Couldn’t send the waiting message. Your comments are kept."
            } else {
                diffCommentStatus = "Delivery is unresolved. Your comments are kept. Resending may send duplicates."
            }
        } else {
            acceptDiffCommentPacket(text)
        }
    }

    func beginHeldDiffComments(_ text: String) -> Bool {
        guard let pending = unresolvedCommentPacket, PromptQuote.trimmed(text) == PromptQuote.trimmed(pending) else {
            return false
        }
        diffCommentSending = true
        diffCommentStatus = "Checking whether your comments arrived…"
        return true
    }

    @discardableResult
    func removeLocallyQueuedDiffComments(_ text: String) -> Bool {
        guard let pending = unresolvedCommentPacket, PromptQuote.trimmed(text) == PromptQuote.trimmed(pending) else {
            return false
        }
        unresolvedCommentPacket = nil
        diffCommentStatus = nil
        return true
    }
}
