import ACP
import Experiments
import SwiftUI

/// How a transcript presents its rows. Each style is a whole implementation behind this contract:
/// the standard one, and alternatives experiments contribute through `.transcriptStyle`. The
/// transcript itself (scrolling, loading and empty states) stays the same whichever style is on.
nonisolated protocol TranscriptStyle: Sendable {
    associatedtype Body: View

    /// The rows, top to bottom, ending with the working indicator while the agent works.
    @MainActor @ViewBuilder func makeBody(_ transcript: TranscriptStyleConfiguration) -> Body
}

extension ExtensionPoint where Contract == any TranscriptStyle {
    nonisolated static var transcriptStyle: Self {
        Self(id: "transcript.style", title: "Transcript style", default: StandardTranscriptStyle())
    }
}

/// What a style presents, worked out once so every style follows the same rules: which rows there
/// are, which pending request answers the permission shortcuts, and how to name other sessions.
struct TranscriptStyleConfiguration {
    let session: SessionModel
    let rows: [TranscriptRow]
    let openSubagent: (SessionID) -> Void
    /// Another session's title, for naming the tasks this one exchanges messages with.
    let sessionTitle: (SessionID) -> String?

    /// Only the oldest pending request answers the permission shortcuts, so they're never ambiguous.
    var shortcutTarget: String? {
        session.state.pendingPermissions.first?.toolCallID
    }

    var isWorking: Bool {
        session.phase == .prompting
    }

    /// How to refer to another session in this transcript's session messages.
    func name(for id: SessionID?) -> String {
        if let subagent = session.state.subagents.first(where: { $0.id == id }) {
            return subagent.title ?? "subagent"
        }
        if let id, id == session.parentID {
            return "the parent session"
        }
        if let id, let title = sessionTitle(id) {
            return title
        }
        // A sibling task, or a session this one can't name yet.
        return "another task"
    }
}

// The leaf rows every style shows the same way, wired to the session.
extension TranscriptStyleConfiguration {
    func toolCall(_ call: ToolCallState) -> some View {
        ToolCallView(call: call) { option in
            Task { await session.choose(option, forToolCall: call.id) }
        }
        .environment(\.permissionShortcutsEnabled, call.id == shortcutTarget)
    }

    func exploration(_ calls: [ToolCallState]) -> some View {
        // Calls waiting for approval are never folded, so a group has nothing to answer.
        ToolActivityGroupView(calls: calls) { _ in }
    }

    func subagent(_ subagent: SubagentState) -> some View {
        SubagentCard(subagent: subagent) { openSubagent(subagent.id) }
    }

    func sessionMessage(_ message: SessionMessage) -> some View {
        SessionMessageView(message: message, sessionID: session.id, name: name(for:))
    }
}
