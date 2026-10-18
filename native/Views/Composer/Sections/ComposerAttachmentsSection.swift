import ACP
import QuickLook
import SwiftUI

/// The files and images going out with the draft, as a row of chips above the text, followed by
/// any still being read.
struct ComposerAttachmentsSection: View {
    let attachments: [PromptAttachment]
    let pending: [ComposerPendingAttachment]
    let missing: Set<PromptAttachment.ID>
    /// What the agent takes, so a picture that will go as a path says so before it's sent.
    let capabilities: PromptCapabilities
    let agentName: String
    let onRemove: (PromptAttachment.ID) -> Void

    @State private var previewing: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DS.Space.sm) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentChip(
                        attachment: attachment,
                        pathOnlyReason: ComposerAttachmentNote.pathOnlyReason(
                            for: attachment, capabilities: capabilities, agentName: agentName),
                        isMissing: missing.contains(attachment.id),
                        onPreview: { previewing = attachment.url },
                        onRemove: { onRemove(attachment.id) }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                ForEach(pending) { pending in
                    ComposerPendingAttachmentChip(pending: pending)
                        .transition(.opacity)
                }
            }
            .padding(DS.Space.md)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .quickLookPreview($previewing, in: attachments.map(\.url))
        .animation(.dsQuick, value: attachments.map(\.id))
        .animation(.dsQuick, value: pending)
    }
}
