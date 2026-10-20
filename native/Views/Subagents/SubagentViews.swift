import ACP
import NativeOrchestration
import SwiftUI

/// A subagent's entry in its parent's transcript: who it is, what it's doing, and a way into its
/// own conversation.
struct SubagentCard: View {
    let subagent: SubagentState
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
                Image(systemName: "person.2.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.dsTextSecondary)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(subagent.title ?? "Subagent")
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let description = subagent.description, !description.isEmpty {
                        Text(description)
                            .font(.dsBody)
                            .foregroundStyle(.dsTextSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: DS.Space.md)
                SubagentStatusLabel(state: subagent.workState)
                Image(systemName: "chevron.right")
                    .font(.ds(10, weight: .semibold))
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.lg)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.card)
                    .strokeBorder(
                        subagent.workState == .requiresAction
                            ? Color.dsAttention.opacity(0.6) : .dsSeparator)
            }
            .contentShape(.rect(cornerRadius: DS.Radius.card))
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
        HStack(spacing: DS.Space.xs) {
            switch state {
            case .running:
                DotGridLoader(pattern: .typing)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                    .accessibilityHidden(true)
                Text("Working")
            case .requiresAction:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.dsAttention)
                Text("Needs approval")
            case .idle(let stopReason, let error):
                switch stopReason {
                case .error:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.dsDanger)
                    Text("Failed")
                        .help(error?.message ?? "The subagent's work failed.")
                case .cancelled:
                    Image(systemName: "stop.circle")
                    Text("Stopped")
                default:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.dsSuccess)
                    Text("Done")
                }
            case .unknown, .other, nil:
                Image(systemName: "questionmark.circle")
                Text("Unknown")
            }
        }
        .font(.dsMicro)
        .foregroundStyle(.dsTextSecondary)
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
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Label(title, systemImage: isOutgoing ? "arrow.up.right" : "arrow.down.left")
                .font(.ds(10, weight: .medium))
                .foregroundStyle(.dsTextSecondary)
            MarkdownView(text)
        }
        .padding(.leading, DS.Space.lg)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(Color.dsAccent.opacity(0.5))
                .frame(width: TranscriptMetrics.sessionMessageRailWidth)
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

#if DEBUG
#Preview("Subagent cards") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            ForEach(SubagentPreviewFixtures.subagents) { subagent in
                SubagentCard(subagent: subagent, onOpen: {})
            }
        }
        .frame(width: 560)
    }
}

#Preview("Session messages") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SessionMessageView(
                title: "To Explore", isOutgoing: true,
                text: "Find where the composer queues follow-ups and how Send Now reorders them.")
            SessionMessageView(
                title: "From Explore", isOutgoing: false,
                text: "Follow-ups queue in SessionModel+Turns.swift. Send Now steers when the agent can.")
        }
        .frame(width: 560)
    }
}
#endif
