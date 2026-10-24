import ACP
import SwiftUI

/// One trailing-aligned group above a user message, preserving the order the files were attached.
struct UserMessageAttachmentsView: View {
    let attachments: [MessageAttachment]

    var body: some View {
        if attachments.count == 1, let attachment = attachments.first {
            UserMessageAttachmentTile(attachment: attachment, isSingle: true)
        } else {
            FlowLayout(spacing: DS.Space.sm, alignment: .trailing) {
                ForEach(attachments) { attachment in
                    UserMessageAttachmentTile(attachment: attachment)
                }
            }
        }
    }
}

#if DEBUG
#Preview("User attachments - Single images") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.lg) {
            UserMessageAttachmentsView(attachments: [UserMessageAttachmentsPreviewFixtures.wide])
            UserMessageAttachmentsView(attachments: [UserMessageAttachmentsPreviewFixtures.tall])
        }
        .frame(width: 300)
        .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
    }
}

#Preview("User attachments - Mixed and wrapping") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.xxl) {
            ForEach([2, 3, 6], id: \.self) { count in
                UserMessageAttachmentsView(
                    attachments: Array(UserMessageAttachmentsPreviewFixtures.mixed.prefix(count)))
            }
        }
        .frame(width: 340)
        .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
    }
}

#Preview("User attachments - Narrow, files and unavailable image") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.lg) {
            UserMessageAttachmentsView(attachments: UserMessageAttachmentsPreviewFixtures.files)
            UserMessageAttachmentsView(attachments: [UserMessageAttachmentsPreviewFixtures.wide])
        }
        .frame(width: 140)
        .environment(\.openTranscriptArtifact, TranscriptArtifactOpener(session: nil, filesAreLocal: true))
    }
}
#endif
