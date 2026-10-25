import ACP
import SwiftUI

/// A source's identity travels through the shared transcript and Changes views. The model owns
/// pending line selections, so the menu and on-screen action use the same quote.
struct ComposerQuoteContext: Equatable {
    let task: UUID
    let quotes: [PromptQuote]
    let selectedSource: UUID?
    let select: (UUID, [PromptQuote]) -> Void
    let quote: ([PromptQuote]) -> Void
    let clear: (UUID) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.task == rhs.task && lhs.quotes == rhs.quotes && lhs.selectedSource == rhs.selectedSource
    }
}

struct ComposerQuoteSource: Equatable {
    var name: String
    var text: String?
    var firstLine = 1
    var side = PromptQuote.Side.transcript
}

extension EnvironmentValues {
    @Entry var composerQuoteContext: ComposerQuoteContext?
}

extension View {
    func composerQuoteSource(_ source: ComposerQuoteSource) -> some View {
        modifier(ComposerQuoteSourceModifier(source: source))
    }
}

private struct ComposerQuoteSourceModifier: ViewModifier {
    let source: ComposerQuoteSource
    @Environment(\.composerQuoteContext) private var context

    func body(content: Content) -> some View {
        if let context {
            content
                .background { PlatformQuoteSelectionAnchor(task: context.task, source: source).allowsHitTesting(false) }
                .contextMenu {
                    Button("Quote Selected Lines") {
                        if let quotes = PlatformQuoteSelection.capture(task: context.task, source: source) {
                            context.quote(quotes)
                        }
                    }
                    .disabled(PlatformQuoteSelection.capture(task: context.task, source: source) == nil)
                }
        } else {
            content
        }
    }
}
