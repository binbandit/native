import ACP
import SwiftUI

struct ComposerQuotesSection: View {
    let quotes: [PromptQuote]
    let remove: (Int) -> Void
    var edit: ((PromptQuote) -> Void)?

    var body: some View {
        CappedHeightScrollView(maxHeight: DS.ComposerQuote.maxHeight) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(quotes.indices, id: \.self) { index in
                    quote(quotes[index], index: index)
                }
            }
            .padding(.top, quotes.contains { $0.comment != nil } ? DS.Space.md : DS.ComposerQuote.top)
            .padding(.bottom, quotes.contains { $0.comment != nil } ? DS.Space.sm : DS.ComposerQuote.bottom)
            .padding(.horizontal, DS.ComposerQuote.inset)
        }

    }

    private func quote(_ quote: PromptQuote, index: Int) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DiffCommentsSourceQuote(quote: quote)
                .padding(.trailing, DS.Size.controlXS)
                .overlay(alignment: .topTrailing) {
                    Button {
                        remove(index)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.dsTextTertiary)
                    .dsHitTarget(DS.ComposerSettings.controlHeight)
                    .accessibilityLabel("Remove \(quote.comment == nil ? "Quote" : "Comment") from \(quote.source)")
                }
                .contextMenu {
                    if quote.comment != nil, let edit {
                        Button("Edit Comment") { edit(quote) }
                    }
                    Button("Remove") { remove(index) }
                }

        }
    }

}

#if DEBUG
#Preview("Quotes - Diff, output, long source and narrow") {
    DSPreviewPair {
        ComposerSurface {
            ComposerQuotesSection(
                quotes: [
                    PromptQuote(
                        source: "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift", side: .new,
                        lines: [
                            .init(number: 44, text: "prompts.remove(at: index)"),
                            .init(number: 45, text: "prompts.append(edited)"),
                        ]),
                    PromptQuote(
                        source: "swift test --filter PromptQueueTests",
                        lines: [
                            .init(
                                number: 1044,
                                text: "Test failed: an edit should keep the first message in its original place."),
                            .init(number: 1045, text: ""),
                        ]),
                ], remove: { _ in })
        }
        .frame(width: 420)
    }
}
#endif
