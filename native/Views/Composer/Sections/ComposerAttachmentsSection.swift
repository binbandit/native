import ACP
import QuickLook
import SwiftUI

/// The files and images going out with the draft, as chips above the text, followed by any still
/// being read. Past three rows they scroll.
struct ComposerAttachmentsSection: View {
    let attachments: [PromptAttachment]
    let pending: [ComposerPendingAttachment]
    let missing: Set<PromptAttachment.ID>
    /// The chip the keyboard has selected, from the text with ←.
    let selected: PromptAttachment.ID?
    /// What the agent takes, so a picture that will go as a path says so before it's sent.
    let capabilities: PromptCapabilities
    let agentName: String
    let onRemove: (PromptAttachment.ID) -> Void

    @State private var previewing: URL?

    var body: some View {
        CappedHeightScrollView(maxHeight: ComposerMetrics.attachmentsMaxHeight) {
            FlowLayout(spacing: DS.Space.sm) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentChip(
                        attachment: attachment,
                        pathOnlyReason: ComposerAttachmentNote.pathOnlyReason(
                            for: attachment, capabilities: capabilities, agentName: agentName),
                        isMissing: missing.contains(attachment.id),
                        isSelected: attachment.id == selected,
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.md)
        }
        .quickLookPreview($previewing, in: attachments.map(\.url))
        .animation(.dsQuick, value: attachments.map(\.id))
        .animation(.dsQuick, value: pending)
    }
}

#if DEBUG
#Preview("Attachments section") {
    let attachments = ComposerPreviewFixtures.attachments
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                ComposerAttachmentsSection(
                    attachments: attachments, pending: [ComposerPendingAttachment(name: "Recording.mov")], missing: [],
                    selected: nil, capabilities: PromptCapabilities(image: true, embeddedContext: true),
                    agentName: "Claude Code", onRemove: { _ in })
            }
            // An agent that takes neither images nor embedded files, with one file gone from disk.
            ComposerSurface {
                ComposerAttachmentsSection(
                    attachments: attachments, pending: [], missing: [attachments[0].id], selected: attachments[2].id,
                    capabilities: PromptCapabilities(), agentName: "Codex", onRemove: { _ in })
            }
        }
        .frame(width: 560)
    }
}
#endif
