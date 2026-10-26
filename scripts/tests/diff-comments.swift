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
        require(session.diffComments.isEmpty && session.draft.isEmpty, "Only accepted packet clears")
        session.draft = oldDraft
        session.unresolvedCommentPacket = oldDraft
        require(session.diffCommentSendBlock != nil, "Unresolved delivery blocks a second send")
        session.diffCommentSending = false
        session.reconcileDiffCommentDelivery()
        require(
            session.unresolvedCommentPacket == nil && session.draft.isEmpty,
            "Queue evidence resolves the original packet")
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
        print(
            "PASS: add, cancel, edit, undo/redo, clear, unfinished guard, one queued packet, acknowledgement evidence, managed send, retention and durable recovery"
        )
    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }
    private struct MissingFixture: Error {}
}
