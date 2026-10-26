import NativePolicy
import SwiftUI

struct DiffCommentsDeliveryStatus: View {
    let session: SessionModel
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let block = session.sourceExcerptBlock(for: session.draft) {
                Text(block)
                Text(session.diffCommentManagedExplanation).foregroundStyle(.dsTextSecondary)
                if let contact = session.diffCommentsPolicy().organizationContact, let url = URL(string: contact) {
                    Link("Request a Change…", destination: url)
                }
            } else if let status = session.diffCommentStatus
                ?? (session.unresolvedCommentPacket == nil
                    ? nil : "Delivery is unresolved. Your comments are kept. Resending may send duplicates.")
            {
                HStack(spacing: DS.Space.md) {
                    if session.diffCommentSending {
                        DotGridLoader(pattern: .waiting)
                            .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                    }
                    Text(status)
                    if !session.diffCommentSending, session.unresolvedCommentPacket == nil,
                        status.hasPrefix("Couldn’t send")
                    {
                        Button("Try Again", action: retry).buttonStyle(.ds(.ghost))
                    }
                }
                if !session.diffCommentSending, session.unresolvedCommentPacket != nil {
                    Button("Allow Resend - May Send Duplicates") { session.allowDiffCommentResend() }
                        .buttonStyle(.ds(.ghost))
                }
            }
        }
        .font(DS.ComposerQuote.headerFont)
        .foregroundStyle(.dsTextSecondary)
        .padding(.horizontal, DS.ComposerQuote.inset)
        .padding(.bottom, DS.Space.md)
    }
}

#if DEBUG
#Preview("DiffCommentsDeliveryStatus - States") {
    DSPreviewPair {
        VStack {
            DiffCommentsPreviewHost("C8") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
            DiffCommentsPreviewHost("C11") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
            DiffCommentsPreviewHost("C13") { DiffCommentsDeliveryStatus(session: $0, retry: {}) }
        }.frame(width: 548)
    }
}
#endif
