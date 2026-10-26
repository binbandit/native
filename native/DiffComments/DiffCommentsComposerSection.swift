import ACP
import SwiftUI

struct DiffCommentsComposerSection: View {
    let session: SessionModel
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: "text.bubble")
                Text("\(session.diffComments.count) comments from Changes")
                Spacer(minLength: DS.Space.xs)
                Button(session.diffCommentsExpanded ? "Collapse" : "Review") { session.toggleDiffCommentsReview() }
                    .buttonStyle(.ds(.ghost))
                    .accessibilityLabel("Review Draft Comments")
            }
            .font(DS.ComposerQuote.headerFont)
            .foregroundStyle(.dsTextSecondary)
            .padding(.leading, DS.ComposerQuote.inset)
            .padding(.trailing, DS.ComposerSettings.trailingInset)
            .frame(minHeight: DS.DiffComments.summaryHeight)
            .contextMenu {
                Button("Review Draft Comments") { session.reviewDiffComments() }
                Button("Clear Comments") { session.clearDiffComments(undoManager: undoManager) }
            }
            .accessibilityLabel("\(session.diffComments.count) draft comments from Changes")
            if session.diffCommentsExpanded {
                SeparatorLine()
                ComposerQuotesSection(
                    quotes: session.composerQuotes,
                    remove: {
                        session.removeQuote(at: $0, undoManager: undoManager)
                    }, edit: { session.editDiffComment($0, inComposer: true) })
            } else {
                let bare = session.composerQuotes.enumerated().filter { $0.element.comment == nil }
                if !bare.isEmpty {
                    ComposerQuotesSection(
                        quotes: bare.map(\.element),
                        remove: {
                            session.removeQuote(at: bare[$0].offset, undoManager: undoManager)
                        })
                }
            }
        }
        .environment(\.diffCommentsSession, session)
    }
}

#if DEBUG
#Preview("DiffCommentsComposerSection - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C5") { session in
            ComposerSurface { DiffCommentsComposerSection(session: session) }.frame(width: 548)
        }
    }
}
#endif
