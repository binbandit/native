import SwiftUI

/// The window as one stacked bar: built-in, the user's setup, the conversation, then the free space
/// as the bar's own track and the compaction buffer at the far end. Each segment says what it is on
/// hover; the category table under it carries the same numbers for everyone else.
struct ContextBar: View {
    let composition: ContextComposition

    var body: some View {
        GeometryReader { proxy in
            let layout = ContextBarLayout(composition, width: proxy.size.width, gap: DS.Space.xxs, minWidth: DS.Space.xxs, mergeBelow: DS.Space.xs)
            HStack(spacing: DS.Space.xxs) {
                ForEach(layout.pieces) { piece in
                    Rectangle()
                        .fill(piece.kind.color)
                        .frame(width: piece.width)
                        .help(tooltip(for: piece))
                }
            }
        }
        .frame(height: UsageMetrics.barHeight)
        .clipShape(.rect(cornerRadius: DS.Radius.small, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context window")
        .accessibilityValue("\(DSFormat.tokens(composition.usedTokens)) of \(DSFormat.tokens(composition.windowTokens)) tokens in use")
    }

    private func tooltip(for piece: ContextBarLayout.Piece) -> String {
        "\(piece.names.joined(separator: ", ")) · \(DSFormat.tokens(piece.tokens)) · \(DSFormat.share(piece.tokens, of: composition.windowTokens))"
    }
}
