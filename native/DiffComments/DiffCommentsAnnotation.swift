import ACP
import SwiftUI

struct DiffCommentsAnnotation: View {
    let session: SessionModel
    let quote: PromptQuote
    let stale: Bool
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.md) {
                Text("In draft · \(DiffCommentsSourceQuote.label(quote))")
                    .font(DS.ComposerQuote.headerFont)
                    .foregroundStyle(.dsTextSecondary)
                Spacer(minLength: DS.Space.xs)
                Button("Edit") { session.editDiffComment(quote) }
                    .buttonStyle(.ds(.ghost))
            }
            Text(verbatim: quote.comment?.body ?? "").font(.dsCallout).foregroundStyle(.dsTextPrimary)
            if stale {
                if quote.comment?.isEarlierVersion == true {
                    Text("Earlier version").font(.dsCaption).foregroundStyle(.dsTextSecondary)
                } else {
                    Text("These lines changed. Your original selection is kept.")
                        .font(DS.ComposerQuote.headerFont).foregroundStyle(.dsDanger)
                }
                DiffCommentsSourceQuote(quote: quote)
                if let id = quote.comment?.id, quote.comment?.isEarlierVersion != true {
                    HStack(spacing: DS.Space.md) {
                        Button("Keep Original") { session.keepOriginalDiffComment(id, undoManager: undoManager) }
                            .buttonStyle(.ds(.secondary))
                        Button("Select New Lines") { session.beginReanchoringDiffComment(id) }
                            .buttonStyle(.ds(.ghost))
                    }
                }
            }
        }
        .padding(.leading, DS.Space.lg)
        .overlay(alignment: .leading) { Rectangle().fill(.dsBorder).frame(width: DS.DiffComments.hairline) }
        .padding(.leading, DS.DiffComments.anchorInset)
        .padding(.trailing, DS.Space.xl)
        .padding(.vertical, DS.Space.md)
        .contextMenu {
            Button("Edit") { session.editDiffComment(quote) }
            Button("Remove") {
                if let index = session.composerQuotes.firstIndex(of: quote) {
                    session.removeQuote(at: index, undoManager: undoManager)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Draft comment on \(quote.source), \(DiffCommentsSourceQuote.label(quote))")
        .accessibilityAction(named: "Edit") { session.editDiffComment(quote) }
        .accessibilityAction(named: "Remove") {
            if let index = session.composerQuotes.firstIndex(of: quote) {
                session.removeQuote(at: index, undoManager: undoManager)
            }
        }
    }
}

#if DEBUG
#Preview("DiffCommentsAnnotation - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C4") { session in
            if let quote = session.diffComments.first {
                VStack {
                    DiffCommentsAnnotation(session: session, quote: quote, stale: false);
                    DiffCommentsAnnotation(session: session, quote: quote, stale: true)
                }.frame(width: DS.DiffComments.referencePaneWidth)
            }
        }
    }
}
#endif
