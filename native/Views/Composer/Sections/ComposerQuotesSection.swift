import ACP
import SwiftUI

struct ComposerQuotesSection: View {
    let quotes: [PromptQuote]
    let remove: (Int) -> Void

    var body: some View {
        CappedHeightScrollView(maxHeight: DS.ComposerQuote.maxHeight) {
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(quotes.indices, id: \.self) { index in
                    quote(quotes[index], index: index)
                }
            }
            .padding(.top, DS.ComposerQuote.top)
            .padding(.bottom, DS.ComposerQuote.bottom)
            .padding(.horizontal, DS.ComposerQuote.inset)
        }

    }

    private func quote(_ quote: PromptQuote, index: Int) -> some View {
        let lines = quote.displayLines
        return VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "text.quote")
                Text(quote.source.split(separator: "/").last.map(String.init) ?? quote.source)
                    .font(DS.ComposerQuote.codeFont)
                    .foregroundStyle(.dsTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(quote.source)
                Text(lineLabel(quote))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: DS.Space.xs)
                Button {
                    remove(index)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .dsHitTarget(DS.ComposerSettings.controlHeight)
                .accessibilityLabel("Remove Quote from \(quote.source)")
            }
            .font(DS.ComposerQuote.headerFont)
            .foregroundStyle(.dsTextTertiary)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { offset in
                    Text(verbatim: lines[offset].text.isEmpty ? " " : lines[offset].text)
                        .font(DS.ComposerQuote.codeFont)
                        .foregroundStyle(.dsTextPrimary)
                        .frame(minHeight: DS.ComposerQuote.lineHeight, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .topLeading) {
                            Text(verbatim: String(lines[offset].number))
                                .font(DS.ComposerQuote.numberFont)
                                .foregroundStyle(.dsTextQuaternary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: DS.ComposerQuote.inset - DS.ComposerQuote.numberGap, alignment: .trailing)
                                .offset(x: -DS.ComposerQuote.inset)
                                .accessibilityHidden(true)
                        }
                        .accessibilityLabel("Line \(lines[offset].number), \(lines[offset].text)")
                }
            }
        }
    }

    private func lineLabel(_ quote: PromptQuote) -> String {
        guard let first = quote.lines.first?.number, let last = quote.lines.last?.number else { return "" }
        let range = first == last ? "line \(first)" : "lines \(first)-\(last)"
        switch quote.side {
        case .transcript: return range
        case .new: return "\(range), after the change"
        case .old: return "\(range), before the change"
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
