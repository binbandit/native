import ACP
import SwiftUI

/// Follow-ups waiting for the turn to end, as the composer's top section. The first goes out next.
/// Each can be sent now (steered into the running turn, or sent after stopping it when the agent
/// can't steer), edited in the composer, moved (drag, its menu, or ⌥⌘↑ / ⌥⌘↓ while it's open in the
/// editor) or removed.
struct QueuedPromptsSection: View {
    typealias Prompt = SessionModel.QueuedPrompt

    let prompts: [Prompt]
    /// The prompt open in the editor, if any.
    let editing: Prompt.ID?
    /// How Send Now delivers a message right now; nil when it can't.
    let sendNow: SessionModel.SendNowRoute?
    let agentName: String
    let onSendNow: (Prompt.ID) -> Void
    let onMove: (Prompt.ID, PromptQueue.Direction) -> Void
    /// A drag dropped the first message just before the second, or last with no second.
    let onDrop: (Prompt.ID, Prompt.ID?) -> Void
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
                    canMoveUp: index > 0,
                    canMoveDown: index < prompts.count - 1,
                    sendNow: sendNow.map { QueuedSendNow(route: $0, agentName: agentName) },
                    onSendNow: onSendNow,
                    onMove: onMove,
                    onDrop: onDrop,
                    onEdit: onEdit,
                    onRemove: onRemove
                )
            }
        }
        .font(.dsBody)
        .padding(DS.Space.md)
        // A message dragged below the last row goes to the back.
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDrop(id, nil)
            return true
        }
    }
}

/// What Send Now does for a queued message, said in its help.
struct QueuedSendNow {
    let route: SessionModel.SendNowRoute
    let agentName: String

    var help: String {
        switch route {
        case .steer: "Send Now: add it to \(agentName)’s running turn"
        case .interrupt:
            "Send Now: stop \(agentName)’s turn, then send it (\(agentName) can’t add a message to a turn in progress)"
        case .send: "Send Now: send it as the next message"
        }
    }
}

private struct QueuedPromptRow: View {
    typealias Prompt = SessionModel.QueuedPrompt

    let prompt: Prompt
    let isNext: Bool
    let isEditing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let sendNow: QueuedSendNow?
    let onSendNow: (Prompt.ID) -> Void
    let onMove: (Prompt.ID, PromptQueue.Direction) -> Void
    let onDrop: (Prompt.ID, Prompt.ID?) -> Void
    let onEdit: (Prompt) -> Void
    let onRemove: (Prompt.ID) -> Void

    @State private var isHovered = false
    @State private var isDropTarget = false
    @FocusState private var focusedAction: String?

    var body: some View {
        HStack(spacing: DS.Space.md) {
            // One line each; the full text is a click (or ↑) away in the editor.
            HStack(spacing: DS.Space.sm) {
                // A message of files alone reads as their names.
                Text(verbatim: prompt.text.isEmpty ? prompt.attachments.map(\.name).joined(separator: ", ") : line)
                    .foregroundStyle(isEditing || prompt.text.isEmpty ? .dsTextTertiary : .dsTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !prompt.attachments.isEmpty {
                    // The files wait with it, and go out with it.
                    Label("\(prompt.attachments.count)", systemImage: "paperclip")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .help(prompt.attachments.map(\.name).joined(separator: ", "))
                        .accessibilityLabel(
                            prompt.attachments.count == 1 ? "1 attachment" : "\(prompt.attachments.count) attachments")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The actions show on hover, and while one of them has keyboard focus, so rows stay quiet.
            HStack(spacing: DS.Space.xxs) {
                if let sendNow {
                    action("Send Now", systemImage: "arrow.up", help: sendNow.help) { onSendNow(prompt.id) }
                }
                action("Edit Message", systemImage: "square.and.pencil") { onEdit(prompt) }
                action("Remove from Queue", systemImage: "trash") { onRemove(prompt.id) }
            }
            .opacity(!ComposerPlatform.revealsControlsOnHover || isHovered || focusedAction != nil ? 1 : 0)
        }
        .padding(.vertical, DS.Space.xs)
        .padding(.horizontal, DS.Space.md)
        .frame(minHeight: DS.Size.listRow)
        .background(isNext ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.control, style: .continuous))
        // Where a dragged message lands: just above this one.
        .overlay(alignment: .top) {
            if isDropTarget {
                // Centered in the gap between rows, as the sidebar marks a drop.
                Capsule()
                    .fill(.dsTextTertiary)
                    .frame(height: DS.Space.xxs)
                    .padding(.horizontal, DS.Space.xs)
                    .offset(y: -DS.Space.xxs)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(.rect)
        .onTapGesture { onEdit(prompt) }
        // Dragged by its id; dropping on a row puts it there, pushing that row down.
        .draggable(prompt.id.uuidString) {
            ComposerSurface(isFloating: true) {
                Text(verbatim: line)
                    .font(.dsBody)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, DS.Space.md)
                    .padding(.vertical, DS.Space.sm)
            }
        }
        .dropDestination(for: String.self) { ids, _ in
            guard let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDrop(id, prompt.id)
            return true
        } isTargeted: {
            isDropTarget = $0
        }
        // The same actions without hovering: long-press on iPad, right-click on the Mac.
        .contextMenu {
            if let sendNow {
                Button("Send Now", systemImage: "arrow.up") { onSendNow(prompt.id) }
                    .help(sendNow.help)
            }
            Button("Edit Message", systemImage: "square.and.pencil") { onEdit(prompt) }
            Divider()
            Button("Move Up", systemImage: "arrow.up.to.line") { onMove(prompt.id, .up) }
                .disabled(!canMoveUp)
            Button("Move Down", systemImage: "arrow.down.to.line") { onMove(prompt.id, .down) }
                .disabled(!canMoveDown)
            Divider()
            Button("Remove from Queue", systemImage: "trash", role: .destructive) { onRemove(prompt.id) }
        }
        .trackHover($isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(isEditing ? "Editing: \(summary)" : isNext ? "Next: \(summary)" : summary)
        // The hover actions, for VoiceOver and Switch Control, which don't hover.
        .accessibilityAction(named: "Send Now") { if sendNow != nil { onSendNow(prompt.id) } }
        .accessibilityAction(named: "Edit Message") { onEdit(prompt) }
        .accessibilityAction(named: "Remove from Queue") { onRemove(prompt.id) }
        .accessibilityAction(named: "Move Up") { onMove(prompt.id, .up) }
        .accessibilityAction(named: "Move Down") { onMove(prompt.id, .down) }
    }

    private var line: String {
        summary.split(whereSeparator: \.isNewline).joined(separator: " ")
    }

    private var summary: String { PromptQuote.summary(prompt.text) }

    private func action(
        _ title: String, systemImage: String, help: String? = nil, perform: @escaping () -> Void
    ) -> some View {
        ActionIcon(title: title, systemImage: systemImage, help: help ?? title, perform: perform)
            .focused($focusedAction, equals: title)
    }
}

/// An 18pt icon button that brightens on hover.
private struct ActionIcon: View {
    let title: String
    let systemImage: String
    let help: String
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
            .help(help)
    }
}

#if DEBUG
#Preview("Queued messages") {
    let prompts = ComposerPreviewFixtures.queued
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                QueuedPromptsSection(
                    prompts: prompts, editing: nil, sendNow: .steer, agentName: "Claude Code", onSendNow: { _ in },
                    onMove: { _, _ in }, onDrop: { _, _ in }, onEdit: { _ in }, onRemove: { _ in })
            }
            // One open in the editor, on an agent that can't steer.
            ComposerSurface {
                QueuedPromptsSection(
                    prompts: Array(prompts.prefix(2)), editing: prompts[1].id, sendNow: .interrupt, agentName: "Codex",
                    onSendNow: { _ in }, onMove: { _, _ in }, onDrop: { _, _ in }, onEdit: { _ in },
                    onRemove: { _ in })
            }
            ComposerSurface {
                QueuedPromptsSection(
                    prompts: [prompts[0]], editing: nil, sendNow: nil, agentName: "Cursor", onSendNow: { _ in },
                    onMove: { _, _ in }, onDrop: { _, _ in }, onEdit: { _ in }, onRemove: { _ in })
            }
        }
        .frame(width: 560)
    }
}

#Preview("Queued messages - Narrow") {
    DSPreviewPair {
        ComposerSurface {
            QueuedPromptsSection(
                prompts: ComposerPreviewFixtures.queued, editing: nil, sendNow: .steer, agentName: "Claude Code",
                onSendNow: { _ in }, onMove: { _, _ in }, onDrop: { _, _ in }, onEdit: { _ in }, onRemove: { _ in })
        }
        .frame(width: 320)
    }
}

#Preview("Queued messages - Diff comments") {
    DSPreviewPair {
        ComposerSurface {
            QueuedPromptsSection(
                prompts: [
                    .init(
                        PromptQuote.draft(
                            quotes: DiffCommentsPreviewFixtures.quotes(task: UUID()), message: "Please fix both."))
                ], editing: nil, sendNow: .steer, agentName: "Claude Code", onSendNow: { _ in },
                onMove: { _, _ in }, onDrop: { _, _ in }, onEdit: { _ in }, onRemove: { _ in })
        }.frame(width: 548)
    }
}
#endif
