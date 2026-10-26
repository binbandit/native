import ACP
import SwiftUI

/// Shared by composer review and the transcript, including immutable earlier-version snapshots.
struct DiffCommentsSourceQuote: View {
    let quote: PromptQuote
    @Environment(\.diffCommentsSession) private var session
    @State private var showsEarlierSnapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "text.quote")
                Button {
                    showsEarlierSnapshot = session?.focusDiffCommentSource(quote) != true
                } label: {
                    Text((quote.source as NSString).lastPathComponent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Source: \(quote.source)")
                .font(DS.ComposerQuote.codeFont)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1).truncationMode(.middle).help(quote.source)
                Text(Self.label(quote)).lineLimit(1)
            }
            .font(DS.ComposerQuote.headerFont)
            .foregroundStyle(.dsTextTertiary)
            if quote.comment?.isEarlierVersion == true || showsEarlierSnapshot {
                Text("Earlier version").font(.dsCaption).foregroundStyle(.dsTextSecondary)
            }
            ForEach(quote.displayLines.indices, id: \.self) { offset in
                let line = quote.displayLines[offset]
                Text(verbatim: line.text.isEmpty ? " " : line.text)
                    .font(DS.ComposerQuote.codeFont)
                    .foregroundStyle(.dsTextPrimary)
                    .frame(minHeight: DS.ComposerQuote.lineHeight, alignment: .topLeading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        Text(verbatim: String(line.number))
                            .font(DS.ComposerQuote.numberFont).foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.ComposerQuote.inset - DS.ComposerQuote.numberGap, alignment: .trailing)
                            .offset(x: -DS.ComposerQuote.inset)
                            .accessibilityHidden(true)
                    }
                    .accessibilityLabel("Line \(line.number), \(line.text)")
            }
            if let comment = quote.comment {
                Text(verbatim: comment.body).font(.dsCallout).foregroundStyle(.dsTextPrimary)
            }
        }
    }

    static func label(_ quote: PromptQuote) -> String {
        guard let first = quote.lines.first?.number, let last = quote.lines.last?.number else { return "" }
        let range = first == last ? "line \(first)" : "lines \(first)-\(last)"
        return quote.side == .transcript ? range : "\(quote.side == .old ? "Before" : "After") · \(range)"
    }
}

#if DEBUG
#Preview("DiffCommentsSourceQuote - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C5") { session in
            if let quote = session.diffComments.first {
                DiffCommentsSourceQuote(quote: quote).padding(DS.ComposerQuote.inset).frame(width: 500)
            }
        }
    }
}
#endif
