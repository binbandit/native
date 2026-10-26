import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

extension SessionModel {
    /// Conversation replacement keeps these Native-owned drafts with the task, alongside its quotes.
    func adoptDiffCommentDrafts(from source: SessionModel) {
        diffCommentEditors = source.diffCommentEditors
        activeDiffComment = source.activeDiffComment
        diffCommentsExpanded = source.diffCommentsExpanded
        unresolvedCommentPacket = source.unresolvedCommentPacket
        diffCommentStatus = source.diffCommentStatus
        source.diffCommentEditors = []
        source.activeDiffComment = nil
        source.unresolvedCommentPacket = nil
    }

    var diffComments: [PromptQuote] { composerQuotes.filter { $0.comment != nil } }

    func focusDiffCommentSource(_ quote: PromptQuote) -> Bool {
        guard let current = diffCommentSelection, current.source == quote.source,
            current.comment?.fingerprint == quote.comment?.fingerprint,
            current.comment?.scope == quote.comment?.scope
        else { return false }
        diffCommentRequestedSource = quote
        return true
    }

    func selectDiffCommentLines(_ quote: PromptQuote) { diffCommentSelection = quote }

    func beginDiffComment(_ quote: PromptQuote? = nil) {
        diffCommentEditsInComposer = false
        guard acceptsPrompts, diffCommentRetentionAllowed, let selected = quote ?? diffCommentSelection else { return }
        if let existing = diffCommentEditors.first(where: {
            $0.source == selected.source && $0.side == selected.side && $0.lines == selected.lines
                && $0.comment?.fingerprint == selected.comment?.fingerprint
        }) {
            activeDiffComment = existing.comment?.id
        } else {
            diffCommentEditors.append(selected)
            activeDiffComment = selected.comment?.id
        }
        diffCommentFocusRequest += 1
    }

    func updateDiffComment(_ id: UUID, body: String) {
        guard diffCommentRetentionAllowed,
            let index = diffCommentEditors.firstIndex(where: { $0.comment?.id == id })
        else { return }
        diffCommentEditors[index].comment?.body = body
    }

    func collapseDiffComment() {
        activeDiffComment = nil
        diffCommentFocusRequest += 1
    }

    func addDiffComment(_ id: UUID, undoManager: UndoManager? = nil) {
        guard diffCommentRetentionAllowed,
            let index = diffCommentEditors.firstIndex(where: { $0.comment?.id == id }),
            let body = diffCommentEditors[index].comment?.body,
            !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let previous = draft
        let editors = diffCommentEditors
        let quote = diffCommentEditors.remove(at: index)
        var current = PromptQuote.split(draft)
        if let existing = current.quotes.firstIndex(where: { $0.comment?.id == id }) {
            current.quotes[existing] = quote
        } else {
            current.quotes.append(quote)
        }
        draft = PromptQuote.draft(quotes: current.quotes, message: current.message)
        activeDiffComment = nil
        diffCommentFocusRequest += 1
        diffCommentStatus = nil
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] session in
            MainActor.assumeIsolated {
                session.restoreDiffCommentState(previous, editors: editors, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Add Diff Comment")
        diffCommentAnnouncement = "Comment added. \(diffComments.count) comments in draft."
        diffCommentAnnouncementGeneration += 1
    }

    func editDiffComment(_ quote: PromptQuote, inComposer: Bool = false) {
        diffCommentEditsInComposer = inComposer
        if inComposer { diffCommentStatus = "Edit this comment, then add it to your draft." }
        guard let id = quote.comment?.id else { return }
        if !diffCommentEditors.contains(where: { $0.comment?.id == id }) { diffCommentEditors.append(quote) }
        activeDiffComment = id
        diffCommentFocusRequest += 1
    }

    func discardDiffComment(_ id: UUID, undoManager: UndoManager? = nil) {
        let previous = diffCommentEditors
        diffCommentEditors.removeAll { $0.comment?.id == id }
        activeDiffComment = nil
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] session in
            MainActor.assumeIsolated {
                session.restoreDiffCommentState(session.draft, editors: previous, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Discard Draft Comment")
    }

    func reviewDiffComments() {
        diffCommentsExpanded = true
        wantsComposerFocus = true
    }

    func toggleDiffCommentsReview() { diffCommentsExpanded.toggle() }

    func clearDiffComments(undoManager: UndoManager? = nil) {
        let previous = draft
        let current = PromptQuote.split(draft)
        draft = PromptQuote.draft(quotes: current.quotes.filter { $0.comment == nil }, message: current.message)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] session in
            MainActor.assumeIsolated {
                session.restoreDiffCommentState(previous, editors: session.diffCommentEditors, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Clear Comments")
    }

    func keepOriginalDiffComment(_ id: UUID, undoManager: UndoManager? = nil) {
        changeDiffComment(id, undoManager: undoManager) { $0.comment?.isEarlierVersion = true }
    }

    func beginReanchoringDiffComment(_ id: UUID) {
        reanchoringDiffComment = id
        diffCommentSelection = nil
    }

    func reanchorDiffComment(_ id: UUID, undoManager: UndoManager? = nil) {
        guard let selected = diffCommentSelection else { return }
        reanchoringDiffComment = nil
        changeDiffComment(id, undoManager: undoManager) { quote in
            let original = quote.comment
            quote = selected
            if let original, let anchor = selected.comment {
                quote.comment = PromptDiffComment(
                    id: original.id, task: original.task, scope: anchor.scope,
                    fingerprint: anchor.fingerprint, body: original.body)
            }
        }
    }

    private func changeDiffComment(_ id: UUID, undoManager: UndoManager?, change: (inout PromptQuote) -> Void) {
        let previous = draft
        var current = PromptQuote.split(draft)
        guard let index = current.quotes.firstIndex(where: { $0.comment?.id == id }) else { return }
        change(&current.quotes[index])
        draft = PromptQuote.draft(quotes: current.quotes, message: current.message)
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] session in
            MainActor.assumeIsolated {
                session.restoreDiffCommentState(previous, editors: session.diffCommentEditors, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Change Comment Anchor")
    }

    private func restoreDiffCommentState(_ restored: String, editors: [PromptQuote], undoManager: UndoManager?) {
        let previous = draft
        let previousEditors = diffCommentEditors
        draft = restored
        diffCommentEditors = editors
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] session in
            MainActor.assumeIsolated {
                session.restoreDiffCommentState(previous, editors: previousEditors, undoManager: undoManager)
            }
        }
    }

    func reconcileDiffCommentDelivery() {
        guard let packet = unresolvedCommentPacket, !diffCommentSending else { return }
        let ids = Set(PromptQuote.split(packet).quotes.compactMap { $0.comment?.id })
        guard !ids.isEmpty else { return }
        let texts =
            queuedPrompts.map(\.text)
            + state.items.compactMap { item -> String? in
                guard case .message(let message) = item, message.role == .user else { return nil }
                return message.text
            }
        if texts.contains(where: { text in
            ids.isSubset(of: Set(PromptQuote.split(text).quotes.compactMap { $0.comment?.id }))
                && PromptQuote.trimmed(text) == PromptQuote.trimmed(packet)
        }) {
            acceptDiffCommentPacket(packet)
        }
    }

    @discardableResult
    func prepareDiffCommentsSubmission() -> Bool {
        guard
            let editor = diffCommentEditors.first(where: {
                !($0.comment?.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            })
        else { return true }
        activeDiffComment = editor.comment?.id
        diffCommentEditsInComposer = true
        diffCommentsExpanded = true
        diffCommentFocusRequest += 1
        diffCommentStatus = "Add this comment before sending"
        return false
    }

    /// The draft stays durable until the public task submission path confirms acceptance. A lost
    /// reply keeps it locked until evidence or a deliberate resend resolves the uncertainty.
    func submitDiffComments(_ behavior: FollowUpBehavior) async {
        guard !diffCommentSending, unresolvedCommentPacket == nil else { return }
        guard prepareDiffCommentsSubmission() else { return }
        guard diffCommentSendBlock == nil, permissionRequests.isEmpty, pendingQuestion == nil else { return }
        let packet = PromptQuote.trimmed(draft)
        let files = attachments
        diffCommentSending = true
        unresolvedCommentPacket = packet
        diffCommentStatus = "Checking whether your comments arrived…"
        do {
            let delivery: FollowUpDelivery
            if host == nil, canSend, !queuedPrompts.isEmpty {
                hasSubmittedPrompt = true
                queue.resume()
                queue.append(packet, attachments: files)
                drainQueue()
                delivery = .queued
            } else {
                delivery = try await submit(packet, attaching: files, behavior)
            }
            acceptDiffCommentPacket(packet)
            if delivery == .queued {
                diffCommentAnnouncement =
                    "\(PromptQuote.split(packet).quotes.filter { $0.comment != nil }.count) comments queued for \(agentName)"
            }
            attachments.removeAll { files.contains($0) }
        } catch {
            // RPC rejections establish non-delivery. Connection loss after dispatch does not.
            if error is RPCError || error is SendError {
                unresolvedCommentPacket = nil
                diffCommentStatus = "Couldn’t send. Your \(diffComments.count) comments are kept."
            } else {
                diffCommentStatus = "Delivery is unresolved. Your comments are kept. Resending may send duplicates."
            }
        }
        diffCommentSending = false
        reconcileDiffCommentDelivery()
    }

    func acceptDiffCommentPacket(_ packet: String) {
        let accepted = PromptQuote.split(packet)
        let ids = Set(accepted.quotes.compactMap { $0.comment?.id })
        let current = PromptQuote.split(draft)
        draft = PromptQuote.draft(
            quotes: current.quotes.filter { quote in
                if let id = quote.comment?.id { return !ids.contains(id) || !accepted.quotes.contains(quote) }
                return !accepted.quotes.contains(quote)
            }, message: current.message == accepted.message ? "" : current.message)
        unresolvedCommentPacket = nil
        diffCommentStatus = nil
        diffCommentAnnouncement = "\(ids.count) comments sent to \(agentName)"
        diffCommentAnnouncementGeneration += 1
    }

    func allowDiffCommentResend() {
        guard !diffCommentSending else { return }
        unresolvedCommentPacket = nil
        diffCommentStatus = nil
    }
}

struct DiffCommentsUnresolvedDelivery: Error {}
