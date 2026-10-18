import ACP
import SwiftUI

/// A subagent's entry in its parent's transcript: who it is, what it's doing, and a way into its
/// own conversation.
struct SubagentCard: View {
    let subagent: SubagentState
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "person.2.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(subagent.title ?? "Subagent")
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let description = subagent.description, !description.isEmpty {
                        Text(description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                SubagentStatusLabel(state: subagent.workState)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        subagent.workState == .requiresAction
                            ? AnyShapeStyle(.orange.opacity(0.6)) : AnyShapeStyle(.separator))
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .help("Show this subagent's conversation")
        // One button to Accessibility, named by everything the card shows; the loader inside it is
        // decoration, not a busy indicator of its own.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows this subagent's conversation")
        .accessibilityAction { onOpen() }
    }

    private var accessibilityLabel: String {
        [subagent.title ?? "Subagent", subagent.description, SubagentStatusLabel.text(for: subagent.workState)]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: ", ")
    }
}

struct SubagentStatusLabel: View {
    let state: SubagentWorkState?

    /// The label's words, for anything that names the status without showing it.
    static func text(for state: SubagentWorkState?) -> String {
        switch state {
        case .running: "Working"
        case .requiresAction: "Needs approval"
        case .idle(.error, _): "Failed"
        case .idle(.cancelled, _): "Stopped"
        case .idle: "Done"
        case .unknown, .other, nil: "Unknown"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            switch state {
            case .running:
                DotGridLoader(pattern: .typing)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    .accessibilityHidden(true)
                Text("Working")
            case .requiresAction:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("Needs approval")
            case .idle(let stopReason, let error):
                switch stopReason {
                case .error:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Failed")
                        .help(error?.message ?? "The subagent's work failed.")
                case .cancelled:
                    Image(systemName: "stop.circle")
                    Text("Stopped")
                default:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Done")
                }
            case .unknown, .other, nil:
                Image(systemName: "questionmark.circle")
                Text("Unknown")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .symbolRenderingMode(.hierarchical)
        .animation(.smooth, value: state)
    }
}

/// A message between sessions, such as the task a parent gave its subagent. It isn't from the
/// user or to the user, so it reads as a labelled hand-off rather than a chat bubble.
struct SessionMessageView: View {
    /// "From the parent session", "To Fix the bug".
    let title: String
    let isOutgoing: Bool
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: isOutgoing ? "arrow.up.right" : "arrow.down.left")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            MarkdownView(text)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(.tint.opacity(0.5))
                .frame(width: 3)
        }
    }
}

extension SessionMessageView {
    /// A message in a live session; `sessionID` is the transcript it appears in, to tell incoming
    /// from outgoing.
    init(message: SessionMessage, sessionID: SessionID, name: (SessionID?) -> String) {
        let isOutgoing = message.sender == sessionID
        self.init(
            title: isOutgoing ? "To \(name(message.recipient))" : "From \(name(message.sender))",
            isOutgoing: isOutgoing,
            text: message.text)
    }

    /// A task prompt or message replayed by a reloaded session, where it arrives as a framed user
    /// prompt rather than a session message. Names the sender as a live message does, never by id.
    init(frame: TaskPromptFrame) {
        let sender =
            switch frame.sender {
            case .parent:
                "the parent session"
            case .task(let id, let label), .sibling(let id, let label):
                Orchestrator.savedTask(id: id)?.title ?? OrchestrationTask.displayName(fromLabel: label)
                    ?? "another task"
            }
        self.init(title: "From \(sender)", isOutgoing: false, text: frame.body)
    }
}
