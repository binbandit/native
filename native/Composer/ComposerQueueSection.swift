import SwiftUI

/// Presentation only; queue ordering and delivery belong to the session model.
struct ComposerQueueSection: View {
    struct Message: Identifiable {
        let id: UUID
        let text: String
        var attachments: [String] = []
    }

    let messages: [Message]
    var sendNowHelp: String?
    var onSendNow: (UUID) -> Void
    var onRemove: (UUID) -> Void

    var body: some View {
        CappedHeightScrollView(maxHeight: ComposerMetrics.attachmentsMaxHeight) {
            VStack(spacing: DS.Space.xxs) {
                ForEach(messages) { message in
                    HStack(spacing: DS.Space.sm) {
                        Text(
                            verbatim: message.text.isEmpty ? message.attachments.joined(separator: ", ") : message.text
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        .layoutPriority(-1)
                        .help(message.text.isEmpty ? message.attachments.joined(separator: ", ") : message.text)
                        if !message.text.isEmpty, !message.attachments.isEmpty {
                            Label("\(message.attachments.count)", systemImage: "paperclip")
                                .foregroundStyle(.dsTextTertiary)
                                .help(message.attachments.joined(separator: ", "))
                                .accessibilityLabel("\(message.attachments.count) attachments")
                        }
                        if let sendNowHelp {
                            Button("Send now") { onSendNow(message.id) }
                                .buttonStyle(.ds(.ghost))
                                .help(sendNowHelp)
                                .accessibilityIdentifier("composer.queue.send.\(message.id)")
                        }
                        Button("Remove", systemImage: "xmark") { onRemove(message.id) }
                            .buttonStyle(.ds(.ghost, iconOnly: true))
                            .help("Remove from queue")
                            .accessibilityIdentifier("composer.queue.remove.\(message.id)")
                    }
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .padding(.horizontal, DS.Space.sm)
                    .padding(.vertical, DS.Space.xxs)
                    .frame(minHeight: DS.ComposerRow.controlHeight)
                    .background(.dsSurface, in: .rect(cornerRadius: DS.Radius.control))
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Queued message")
                }
            }
        }
        .accessibilityLabel("Queued messages, sent in order")
    }
}

#if DEBUG
#Preview("Composer queue - Mid-turn delivery") {
    DSPreviewPair {
        ComposerQueueSection(
            messages: [
                .init(id: UUID(), text: "Check the narrow layout too."),
                .init(id: UUID(), text: "Then run the focused tests.", attachments: ["Layout.png"]),
            ], sendNowHelp: "Add this message to the running turn after its tools finish",
            onSendNow: { _ in }, onRemove: { _ in }
        ).frame(width: DS.ComposerField.previewWidth)
    }
}

#Preview("Composer queue - No mid-turn delivery, long message and files only") {
    DSPreviewPair {
        ComposerQueueSection(
            messages: [
                .init(
                    id: UUID(),
                    text: "Check that a long queued message stays on one line and leaves room for its Remove action."),
                .init(id: UUID(), text: "", attachments: ["Layout.png", "ComposerField.swift"]),
            ], onSendNow: { _ in }, onRemove: { _ in }
        ).frame(width: DS.ComposerField.narrowWidth)
    }
}
#endif
