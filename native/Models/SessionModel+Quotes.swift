import ACP
import Foundation

extension SessionModel {
    func selectQuote(_ quotes: [PromptQuote], source: UUID) {
        quoteSelection = quotes
        quoteSelectionSource = source
    }

    func clearQuoteSelection(source: UUID) {
        guard quoteSelectionSource == source else { return }
        quoteSelection = []
        quoteSelectionSource = nil
    }

    var composerQuotes: [PromptQuote] { PromptQuote.split(draft).quotes }

    var composerMessage: String {
        get { PromptQuote.split(draft).message }
        set { draft = PromptQuote.draft(quotes: composerQuotes, message: newValue) }
    }

    func quote(_ quotes: [PromptQuote]) {
        guard acceptsPrompts, permissionRequests.isEmpty, !quotes.isEmpty else { return }
        let current = PromptQuote.split(draft)
        draft = PromptQuote.draft(quotes: current.quotes + quotes, message: current.message)
        quoteSelection = []
        quoteSelectionSource = nil
        wantsComposerFocus = true
    }

    func removeQuote(at index: Int, undoManager: UndoManager? = nil) {
        var current = PromptQuote.split(draft)
        guard current.quotes.indices.contains(index) else { return }
        let removed = current.quotes.remove(at: index)
        draft = PromptQuote.draft(quotes: current.quotes, message: current.message)
        undoManager?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                session.restoreQuote(removed, at: index, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Remove Quote")
    }

    private func restoreQuote(_ quote: PromptQuote, at index: Int, undoManager: UndoManager?) {
        var current = PromptQuote.split(draft)
        let index = min(index, current.quotes.count)
        current.quotes.insert(quote, at: index)
        draft = PromptQuote.draft(quotes: current.quotes, message: current.message)
        undoManager?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated { session.removeQuote(at: index, undoManager: undoManager) }
        }
        undoManager?.setActionName("Remove Quote")
    }
}
