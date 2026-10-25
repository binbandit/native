import ACP
import Foundation
import SwiftUI

@testable import Native

@main
@MainActor
private struct ComposerQuoteChecks {
    static func main() throws {
        let app = AppModel.preview(.empty)
        guard let session = SessionModel.preview(in: app) else { throw MissingFixture() }
        let quote = PromptQuote(
            source: "PromptQueue.swift", side: .new,
            lines: [
                .init(number: 44, text: "prompts.remove(at: index)"),
                .init(number: 45, text: "prompts.append(edited)"),
            ])
        session.draft = "Keep it in place."
        session.quote([quote])
        require(session.composerQuotes == [quote], "Quote appears in the model")
        require(session.composerMessage == "Keep it in place.", "Quoting preserves the ordinary draft")
        session.composerMessage += " Add a test."
        require(
            session.draft == quote.prompt + "Keep it in place. Add a test.", "Message editing preserves source text")
        let undo = UndoManager()
        undo.beginUndoGrouping()
        session.removeQuote(at: 0, undoManager: undo)
        undo.endUndoGrouping()
        require(session.draft == "Keep it in place. Add a test.", "Removing leaves the message")
        undo.undo()
        require(session.composerQuotes == [quote], "Undo restores the source snapshot")
        undo.redo()
        require(session.composerQuotes.isEmpty, "Redo removes the quote again")
        undo.undo()
        let cutUndo = UndoManager()
        cutUndo.beginUndoGrouping()
        ComposerEditorUndo.record(
            Binding(get: { session.composerMessage }, set: { session.composerMessage = $0 }), using: cutUndo)
        session.composerMessage = "After cutting"
        cutUndo.endUndoGrouping()
        cutUndo.undo()
        require(session.composerMessage == "Keep it in place. Add a test.", "Cut undo restores canonical text")
        cutUndo.redo()
        require(session.composerMessage == "After cutting", "Cut redo repeats the edit")
        cutUndo.undo()
        var token = AttributedString("PromptQueue.swift +6 −2")
        token[ComposerFileReferenceAttribute.self] = .init(
            raw: "@Packages/ACP/PromptQueue.swift", display: String(token.characters))
        require(
            ComposerFileReferenceAttribute.restoredTokens(in: token).first?.raw == "@Packages/ACP/PromptQueue.swift",
            "Editor attributes carry full paths through undo")
        session.queue.append(session.draft)
        session.draft = ""
        guard let queued = session.queuedPrompts.first else { throw MissingFixture() }
        session.draft = queued.text
        require(session.composerQuotes == [quote], "Reopening a queued message restores quotes")
        require(
            session.promptBlocks(session.draft, attachments: []).contains {
                $0.text?.contains("44 | prompts.remove") == true
            }, "ACP prompt carries source line numbers")
        let source = UUID()
        session.selectQuote([quote], source: source)
        session.clearQuoteSelection(source: UUID())
        require(session.quoteSelection == [quote], "A different source cannot clear the selection")
        session.clearQuoteSelection(source: source)
        require(session.quoteSelection.isEmpty, "Closing the selected source clears it")
        let draftBeforeApproval = session.draft
        session.previewPermissionRequest(command: "swift test", at: .now)
        session.quote([quote])
        require(
            session.draft == draftBeforeApproval, "Approval instructions do not hide new quotes in the ordinary draft")
        print("PASS: quote, edit, remove, undo/redo, queue reopen, ACP payload and source ownership")
    }

    private static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message)
    }
    private struct MissingFixture: Error {}
}
