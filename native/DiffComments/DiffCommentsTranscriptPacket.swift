import ACP
import SwiftUI

struct DiffCommentsTranscriptPacket: View {
    let quotes: [PromptQuote]
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Text("\(quotes.filter { $0.comment != nil }.count) comments on changes")
                .font(DS.ComposerQuote.headerFont).foregroundStyle(.dsTextSecondary)
            ForEach(quotes.indices, id: \.self) { index in
                DiffCommentsSourceQuote(quote: quotes[index])
                    .padding(.leading, DS.ComposerQuote.inset)
            }
            if !message.isEmpty { UserMessageText(text: message) }
        }
        .textSelection(.enabled)
    }
}

#if DEBUG
#Preview("DiffCommentsTranscriptPacket - States") {
    DSPreviewPair {
        DiffCommentsPreviewHost("C5") { session in
            DiffCommentsTranscriptPacket(quotes: session.diffComments, message: "Please make both changes.").padding(
                DS.Space.xl
            ).frame(width: 500)
        }
    }
}
#endif
