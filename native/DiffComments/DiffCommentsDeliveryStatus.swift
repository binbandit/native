import NativePolicy
import SwiftUI

struct DiffCommentsDeliveryStatus: View {
    let session: SessionModel
    let retry: () -> Void
    var showsAttribution = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if showsAttribution {
                HStack(spacing: DS.Space.xs) {
                    Label(session.diffCommentManagedExplanation, systemImage: "lock")
                    if let contact = session.diffCommentsPolicy().organizationContact, let url = URL(string: contact) {
                        Link("Request a Change…", destination: url)
                    }
                }
            } else if let block = session.sourceExcerptBlock(for: session.draft) {
                Label(block, systemImage: "lock")
            } else if let status =
                (session.diffCommentSending ? "Checking whether your comments arrived…" : session.diffCommentStatus)
                ?? (session.unresolvedCommentPacket == nil
                    ? nil
                    : session.hasLocallyQueuedDiffComments
                        ? "Your comments are kept while this task waits to send them."
                        : "Delivery is unresolved. Your comments are kept. Resending may send duplicates.")
            {
                HStack(spacing: DS.Space.md) {
                    if session.diffCommentSending {
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    }
                    Text(status)
                        .foregroundStyle(status.hasPrefix("Couldn’t") ? Color.dsDanger : Color.dsTextSecondary)
                    Spacer(minLength: DS.Space.xs)
                    if !session.diffCommentSending, session.unresolvedCommentPacket == nil,
                        status.hasPrefix("Couldn’t")
                    {
                        Button("Try Again", action: retry).buttonStyle(.ds(.ghost))
                    }
                }
                if !session.diffCommentSending, session.unresolvedCommentPacket != nil {
                    Button(
                        session.hasLocallyQueuedDiffComments ? "Return to Draft" : "Allow Resend - May Send Duplicates"
                    ) { session.allowDiffCommentResend() }
                    .buttonStyle(.ds(.ghost))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(DS.ComposerQuote.headerFont)
        .foregroundStyle(.dsTextSecondary)
        .padding(.horizontal, DS.ComposerQuote.inset)
        .padding(.vertical, DS.Space.md)
    }
}

#if DEBUG
#Preview("DiffCommentsDeliveryStatus - States") {
    DSPreviewPair {
        VStack {
            DiffCommentsPreviewHost("C8") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
            DiffCommentsPreviewHost("C11") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
            DiffCommentsPreviewHost("C13") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
            DiffCommentsPreviewHost("C14") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
        }.frame(width: 548)
    }
}
#endif
