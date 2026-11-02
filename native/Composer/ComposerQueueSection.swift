import ACP
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
    var onEdit: (UUID) -> Void = { _ in }
    var onMove: (UUID, PromptQueue.Direction) -> Void = { _, _ in }
    var onDrop: (UUID, UUID?) -> Void = { _, _ in }

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
                    .contentShape(.rect)
                    .onTapGesture { onEdit(message.id) }
                    .draggable(message.id.uuidString)
                    .dropDestination(for: String.self) { ids, _ in
                        guard let id = ids.first.flatMap(UUID.init(uuidString:)),
                            messages.contains(where: { $0.id == id })
                        else { return false }
                        onDrop(id, message.id)
                        return true
                    }
                    .contextMenu {
                        Button("Edit Message", systemImage: "square.and.pencil") { onEdit(message.id) }
                        if let sendNowHelp {
                            Button("Send now", systemImage: "arrow.up") { onSendNow(message.id) }
                                .help(sendNowHelp)
                        }
                        Divider()
                        Button("Move Up", systemImage: "arrow.up.to.line") { onMove(message.id, .up) }
                            .disabled(message.id == messages.first?.id)
                        Button("Move Down", systemImage: "arrow.down.to.line") { onMove(message.id, .down) }
                            .disabled(message.id == messages.last?.id)
                        Divider()
                        Button("Remove from Queue", systemImage: "trash", role: .destructive) { onRemove(message.id) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Queued message")
                    .accessibilityAction(named: "Edit Message") { onEdit(message.id) }
                    .accessibilityActions {
                        if message.id != messages.first?.id {
                            Button("Move Up") { onMove(message.id, .up) }
                        }
                        if message.id != messages.last?.id {
                            Button("Move Down") { onMove(message.id, .down) }
                        }
                    }
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
