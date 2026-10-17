import SwiftUI

/// Follow-ups waiting for the turn to end, as the composer's top section, after Factory's queued
/// messages panel. The first goes out next. Each can be sent right away (steered into the running
/// turn, when the agent supports it), edited in the composer, or removed.
struct QueuedPromptsSection: View {
    typealias Prompt = SessionModel.QueuedPrompt

    /// How a queued message can skip the wait, if it can.
    enum SendNow {
        /// Into the running turn.
        case steer
        /// As the next prompt, while the agent is idle.
        case send
    }

    let prompts: [Prompt]
    /// The prompt open in the editor, if any.
    let editing: Prompt.ID?
    let sendNow: SendNow?
    let onSendNow: (Prompt.ID) -> Void
    let onEdit: (Prompt) -> Void
    let onRemove: (Prompt.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack {
                Text("Queued messages")
                    .foregroundStyle(.dsTextSecondary)
                Spacer()
                if prompts.count > 1 {
                    Button("Clear all") {
                        prompts.forEach { onRemove($0.id) }
                    }
                    .buttonStyle(.plain)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .help("Remove every queued message")
                }
            }
            ForEach(prompts.indices, id: \.self) { index in
                QueuedPromptRow(
                    prompt: prompts[index],
                    isNext: index == 0,
                    isEditing: prompts[index].id == editing,
                    sendNow: sendNow,
                    onSendNow: onSendNow,
                    onEdit: onEdit,
                    onRemove: onRemove
                )
            }
        }
        .font(.dsBody)
        .padding(DS.Space.md)
    }
}

private struct QueuedPromptRow: View {
    typealias Prompt = SessionModel.QueuedPrompt

    let prompt: Prompt
    let isNext: Bool
    let isEditing: Bool
    let sendNow: QueuedPromptsSection.SendNow?
    let onSendNow: (Prompt.ID) -> Void
    let onEdit: (Prompt) -> Void
    let onRemove: (Prompt.ID) -> Void

    @State private var isHovered = false
    @FocusState private var focusedAction: String?

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // One line each; the full text is a click (or ↑) away in the editor.
            Text(verbatim: prompt.text.split(whereSeparator: \.isNewline).joined(separator: " "))
                .foregroundStyle(isEditing ? .dsTextTertiary : .dsTextPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Like Factory's, the actions show on hover, and while one of them has keyboard focus.
            HStack(spacing: DS.Space.xxs) {
                switch sendNow {
                case .steer: action("Steer Now", systemImage: "chevron.up") { onSendNow(prompt.id) }
                case .send: action("Send Now", systemImage: "chevron.up") { onSendNow(prompt.id) }
                case nil: EmptyView()
                }
                action("Remove from Queue", systemImage: "trash") { onRemove(prompt.id) }
                action("Edit Message", systemImage: "square.and.pencil") { onEdit(prompt) }
            }
            .opacity(!ComposerPlatform.revealsControlsOnHover || isHovered || focusedAction != nil ? 1 : 0)
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.md)
        .frame(minHeight: DS.Size.listRow)
        .background(isNext ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { onEdit(prompt) }
        // The same actions without hovering: long-press on iPad, right-click on the Mac.
        .contextMenu {
            switch sendNow {
            case .steer: Button("Steer Now", systemImage: "chevron.up") { onSendNow(prompt.id) }
            case .send: Button("Send Now", systemImage: "chevron.up") { onSendNow(prompt.id) }
            case nil: EmptyView()
            }
            Button("Edit Message", systemImage: "square.and.pencil") { onEdit(prompt) }
            Button("Remove from Queue", systemImage: "trash", role: .destructive) { onRemove(prompt.id) }
        }
        .trackHover($isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isEditing ? "Editing: \(prompt.text)" : isNext ? "Next: \(prompt.text)" : prompt.text)
    }

    private func action(_ title: String, systemImage: String, perform: @escaping () -> Void) -> some View {
        ActionIcon(title: title, systemImage: systemImage, perform: perform)
            .focused($focusedAction, equals: title)
    }
}

/// An 18pt icon button that brightens on hover (Factory `QueuedMessageActionButton`).
private struct ActionIcon: View {
    let title: String
    let systemImage: String
    let perform: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(title, systemImage: systemImage, action: perform)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.dsCaption)
            .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextTertiary)
            .frame(width: ComposerMetrics.rowActionSize, height: ComposerMetrics.rowActionSize)
            .contentShape(.rect)
            .trackHover($isHovered)
            .help(title)
    }
}
