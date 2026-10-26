import ACP
import Foundation
import NativePolicy
import SwiftUI

@testable import Native

@main
@MainActor
private struct DiffCommentChecks {
    static func main() async throws {
        let app = AppModel.preview(.empty)
        guard let session = SessionModel.preview(in: app) else { throw MissingFixture() }
        let source = DiffCommentsPreviewFixtures.quotes(task: session.clientID)
        guard let first = source.first, let firstID = first.comment?.id else { throw MissingFixture() }
        session.composerMessage = "Keep the draft."
        session.beginDiffComment(first)
        session.updateDiffComment(firstID, body: "First observation\nSecond line")
        session.collapseDiffComment()
        require(session.diffComments.isEmpty, "An unfinished editor is not an added comment")
        session.beginDiffComment(first)
        require(
            session.diffCommentEditors.first?.comment?.body == "First observation\nSecond line",
            "Cancel preserves words")
        let undo = UndoManager()
        undo.beginUndoGrouping()
        session.addDiffComment(firstID, undoManager: undo)
        undo.endUndoGrouping()
        require(session.diffComments.count == 1 && session.diffCommentEditors.isEmpty, "Add moves text into collection")
        require(session.composerMessage == "Keep the draft.", "Add preserves the message")
        undo.undo()
        require(session.diffComments.isEmpty && session.diffCommentEditors.count == 1, "Undo Add restores editor")
        undo.redo()
        require(session.diffComments.count == 1 && session.diffCommentEditors.isEmpty, "Redo Add restores collection")
        session.editDiffComment(session.diffComments[0])
        session.updateDiffComment(firstID, body: "Edited observation")
        session.addDiffComment(firstID)
        require(
            session.diffComments.count == 1 && session.diffComments[0].comment?.body == "Edited observation",
            "Editing preserves identity")
        guard let second = source.last, let secondID = second.comment?.id else { throw MissingFixture() }
        session.beginDiffComment(second)
        await session.submitDiffComments(.queue)
        require(
            session.diffCommentStatus == "Add this comment before sending", "Unfinished text blocks packet submission")
        require(
            session.diffComments.count == 1 && session.queuedPrompts.isEmpty, "Unfinished text never goes out silently")
        session.addDiffComment(secondID)
        let oldDraft = session.draft
        let clearUndo = UndoManager()
        clearUndo.beginUndoGrouping()
        session.clearDiffComments(undoManager: clearUndo)
        clearUndo.endUndoGrouping()
        require(session.diffComments.isEmpty && session.composerMessage == "Keep the draft.", "Clear preserves message")
        clearUndo.undo()
        require(session.draft == oldDraft, "Undo Clear restores complete snapshots")
        clearUndo.redo()
        require(session.diffComments.isEmpty, "Redo Clear works")
        clearUndo.undo()
        session.phase = .prompting
        await session.submitDiffComments(.queue)
        require(session.queuedPrompts.count == 1, "One submission queues one packet")
        require(PromptQuote.split(session.queuedPrompts[0].text).quotes.count == 2, "Both files remain together")
        require(
            session.draft == oldDraft && session.unresolvedCommentPacket != nil, "A local queue keeps durable words")
        let queuedID = session.queuedPrompts[0].id
        session.editingQueuedPrompt = queuedID
        require(session.diffCommentSendBlock == nil, "The owning local queue edit enables its save control")
        session.diffCommentSending = true
        require(session.diffCommentSendBlock != nil, "Concurrent local delivery still blocks saving")
        session.diffCommentSending = false
        session.diffCommentsPolicy = {
            var policy = NativePolicy()
            policy.sourceExcerptsSendingEnabled = false
            return policy
        }
        require(session.diffCommentSendBlock != nil, "Managed source restrictions still block local queue saves")
        session.diffCommentsPolicy = { NativePolicy() }
        session.editingQueuedPrompt = UUID()
        require(session.diffCommentSendBlock != nil, "An unrelated queued edit cannot bypass the pending packet")
        session.editingQueuedPrompt = nil
        session.draft = ""
        session.allowDiffCommentResend()
        require(
            session.diffComments.count == 2 && session.queuedPrompts.isEmpty, "Escape then Return restores the packet")
        require(session.composerMessage == "Keep the draft.", "Return restores the message before deleting recovery")
        session.phase = .prompting
        await session.submitDiffComments(.queue)
        let restoredQueueID = session.queuedPrompts[0].id
        var changed = session.composerQuotes
        changed[0].comment?.body = "A newer observation with the same comment identity"
        let newerPacket = PromptQuote.draft(quotes: changed, message: session.composerMessage)
        session.editingQueuedPrompt = restoredQueueID
        session.draft = newerPacket
        let savedQueueEdit = await session.saveQueuedDiffComments(restoredQueueID)
        require(savedQueueEdit, "Local queue edit is stored")
        require(
            session.queuedPrompts.count == 1
                && PromptQuote.split(session.queuedPrompts[0].text).quotes == changed,
            "Queue edit replaces the packet without adding a message")
        require(
            session.draft == newerPacket && session.unresolvedCommentPacket != nil, "Local edit retains recovery copy")
        session.reconcileDiffCommentDelivery()
        require(session.unresolvedCommentPacket != nil, "An ephemeral queue is not acceptance evidence")
        session.state.appendUserMessage(oldDraft)
        session.reconcileDiffCommentDelivery()
        require(session.unresolvedCommentPacket != nil, "Older evidence cannot acknowledge edited comment contents")
        session.queue.remove(restoredQueueID)
        session.state.appendUserMessage(newerPacket)
        session.reconcileDiffCommentDelivery()
        require(
            session.unresolvedCommentPacket == nil && session.draft.isEmpty, "Actual receipt clears the edited packet")
        session.draft = oldDraft
        session.editingQueuedPrompt = UUID()
        let savedMissingItem = await session.saveQueuedDiffComments(UUID())
        require(!savedMissingItem && session.draft == oldDraft, "Missing queue item preserves the edited packet")
        session.editingQueuedPrompt = nil
        let spaced = PromptQuote.draft(quotes: source, message: "  Please fix this.\n\n")
        session.draft = spaced
        session.acceptDiffCommentPacket(PromptQuote.trimmed(spaced))
        require(session.draft.isEmpty, "Acceptance clears unchanged message text with surrounding whitespace")
        session.draft = oldDraft
        var denied = NativePolicy()
        denied.sourceExcerptsSendingEnabled = false
        session.diffCommentsPolicy = { denied }
        require(session.sourceExcerptBlock(for: session.draft) != nil, "Managed sending is enforced in model")
        do {
            _ = try await session.submit(session.draft, .queue)
            preconditionFailure("Managed packet was submitted")
        } catch SessionModel.SendError.sourceExcerptsProhibited {}
        require(session.draft == oldDraft, "Managed send keeps words")
        denied.sourceExcerptsRetentionEnabled = false
        session.diffCommentsPolicy = { denied }
        session.enforceDiffCommentRetention()
        require(
            session.diffComments.isEmpty && session.composerMessage == "Keep the draft.",
            "Retention removes excerpts without losing message")
        let defaults = PreviewUserDefaults()
        let drafts = ComposerDrafts(defaults: defaults)
        drafts.keep(oldDraft, for: session.key)
        drafts.keepCommentEditors(source, for: session.key)
        drafts.keepCommentDelivery(oldDraft, for: session.key)
        drafts.save()
        let restored = ComposerDrafts(defaults: defaults)
        require(restored.draft(for: session.key) == oldDraft, "Packet survives relaunch")
        require(restored.commentEditors(for: session.key) == source, "Unfinished snapshots survive relaunch")
        require(restored.commentDelivery(for: session.key) == oldDraft, "Unresolved send survives relaunch")
        guard let successor = SessionModel.preview(in: app) else { throw MissingFixture() }
        session.diffCommentsPolicy = { NativePolicy() }
        session.draft = oldDraft
        session.diffCommentEditors = source
        session.unresolvedCommentPacket = oldDraft
        successor.adoptDiffCommentDrafts(from: session)
        require(
            session.diffCommentEditors == source && session.unresolvedCommentPacket == oldDraft,
            "Candidate preparation leaves source-owned comments intact")
        successor.adoptDiffCommentDrafts(from: session, moving: true)
        require(
            successor.diffCommentEditors == source && session.diffCommentEditors.isEmpty,
            "Conversation replacement moves unfinished comments")
        require(successor.draft == oldDraft, "Conversation replacement preserves the complete comment packet")
        try await DiffCommentsHostChecks.run()
        print(
            "PASS: add, cancel, edit, undo/redo, clear, unfinished guard, one queued packet, acknowledgement evidence, managed send, retention, durable recovery and conversation replacement"
        )

    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
    private struct MissingFixture: Error {}
}
