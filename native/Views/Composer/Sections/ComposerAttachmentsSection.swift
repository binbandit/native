import ACP
import SwiftUI

/// The files and images going out with the draft, as a row of chips above the text.
struct ComposerAttachmentsSection: View {
    let attachments: [PromptAttachment]
    let onRemove: (PromptAttachment.ID) -> Void

    @State private var previewing: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.sm) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentChip(
                        attachment: attachment,
                        onPreview: { previewing = attachment.url },
                        onRemove: { onRemove(attachment.id) }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(DS.Space.md)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .quickLookPreview($previewing, in: attachments.map(\.url))
        .animation(.dsQuick, value: attachments.map(\.id))
    }
}
