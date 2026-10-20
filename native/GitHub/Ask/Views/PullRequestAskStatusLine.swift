import SwiftUI

/// What's happening right now, while the agent hasn't answered yet or is still working: the
/// transcript's working indicator with the actual step ("Reading diff/src/app.ts.diff").
struct PullRequestAskStatusLine: View {
    let text: String

    var body: some View {
        HStack(spacing: DS.Space.md) {
            DotGridLoader(pattern: .typing)
                .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            Text(text + "…")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.dsCallout)
        .foregroundStyle(.dsTextSecondary)
        .accessibilityElement(children: .combine)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Ask status line") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            PullRequestAskStatusLine(text: "Reading the pull request's diff and comments")
            PullRequestAskStatusLine(text: "Claude Code stopped. Restarting it to finish the answer")
        }
        .frame(width: PullRequestAskMetrics.panelIdealWidth)
    }
}
#endif
