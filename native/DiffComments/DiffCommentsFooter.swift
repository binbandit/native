import SwiftUI

struct DiffCommentsFooter: View {
    let session: SessionModel
    var body: some View {
        VStack(spacing: 0) {
            SeparatorLine()
            HStack(spacing: DS.Space.md) {
                if session.diffComments.isEmpty {
                    Text(
                        session.diffCommentRetentionAllowed
                            ? "Select a line number, or drag to select a range."
                            : "Saving source comments is restricted by your organization.")
                    Spacer(minLength: DS.Space.xs)
                } else {
                    Image(systemName: "text.bubble")
                    Text(
                        "\(session.diffComments.count) \(session.diffComments.count == 1 ? "comment" : "comments") in your draft"
                    )
                    Spacer(minLength: DS.Space.xs)
                    Button("Review in composer") { session.reviewDiffComments() }.buttonStyle(.ds(.ghost))
                }
            }
            .font(DS.ComposerQuote.headerFont).foregroundStyle(.dsTextSecondary)
            .padding(.horizontal, DS.Space.xl)
            .frame(minHeight: DS.TaskWell.changesHeaderHeight)
        }
        .background(.dsBackground)
    }
}

#if DEBUG
#Preview("DiffCommentsFooter - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C4") { session in
            DiffCommentsFooter(session: session).frame(width: DS.DiffComments.referencePaneWidth)
        }
    }
}
#endif
