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
        wantsComposerFocus = true
    }

    func removeQuote(at index: Int, undoManager: UndoManager? = nil) {
        var current = PromptQuote.split(draft)
        guard current.quotes.indices.contains(index) else { return }
        let removed = current.quotes.remove(at: index)
        draft = PromptQuote.draft(quotes: current.quotes, message: current.message)
        undoManager?.registerUndo(withTarget: self) { session in
            MainActor.assumeIsolated {
                var current = PromptQuote.split(session.draft)
                current.quotes.insert(removed, at: min(index, current.quotes.count))
                session.draft = PromptQuote.draft(quotes: current.quotes, message: current.message)
            }
        }
        undoManager?.setActionName("Remove Quote")
    }
}
