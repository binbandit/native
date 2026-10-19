import Foundation
import NativeCommands

extension CommandID {
    static let sessionClearConversation: Self = "session.clearConversation"
    static let sessionOpenEarlierConversation: Self = "session.openEarlierConversation"
}

extension NativeCommand {
    /// `/clear` from the menu and the palette, and the way back to what it set aside.
    static func clearConversation(model: AppModel) -> [NativeCommand] {
        [
            NativeCommand(
                .sessionClearConversation, title: "Clear Conversation", category: .composer,
                systemImage: "eraser", keywords: ["/clear", "fresh", "reset", "context", "new conversation"]
            ) { context in
                guard let session = context.session else { return }
                Task {
                    do {
                        try await model.clearConversation(of: session)
                    } catch {
                        session.addNotice(
                            "Couldn't clear the conversation: \(error.localizedDescription)", isError: true)
                    }
                }
            }
            .available { context in
                guard let session = context.session else { return false }
                return session.origin == .user && session.acceptsPrompts && !session.isSubagent && session.hasStarted
                    && session.phase == .idle
            },

            NativeCommand(
                .sessionOpenEarlierConversation, title: "Open Earlier Conversation", category: .composer,
                systemImage: "clock.arrow.circlepath", keywords: ["/clear", "previous", "history"]
            ) { context in
                guard let session = context.session else { return }
                model.openConversation(.earlier, from: session.key)
            }
            .available { context in
                context.session.map { model.earlierConversations.conversation(before: $0.key) != nil } ?? false
            },
        ]
    }
}

/// `/clear`, which Native runs itself rather than sending to the agent.
enum ClearConversationCommand {
    static let name = "clear"
    static let summary = "Start a fresh conversation in this task; the earlier one stays a click away"

    /// Whether the draft is just `/clear`.
    static func matches(_ draft: String) -> Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines) == "/\(name)"
    }
}
