/// Contextual keys for code blocks and queued-message edits, as described in docs/keyboard.md.
struct FollowUpHint: Equatable {
    let text: String
    let help: String

    init(text: String, help: String) {
        self.text = text
        self.help = help
    }

    /// The keys for the queued message open in the editor.
    static func editingQueued(sendNow: QueuedSendNow?) -> FollowUpHint {
        let save = "Return: save the edit, keeping its place in the queue"
        let move = "⌥⌘↑ / ⌥⌘↓: move it in the queue\nEscape: close it without saving"
        guard let sendNow else {
            return FollowUpHint(text: "↩ Save · ⌥⌘↑↓ Move", help: "\(save)\n\(move)")
        }
        return FollowUpHint(text: "↩ Save · ⌘↩ Send Now", help: "\(save)\n⌘Return: \(sendNow.help)\n\(move)")
    }

    /// The keys while the caret is in a code block, where Return makes a new line and ⌘Return does
    /// what Return does elsewhere (`primary`).
    static func inCodeBlock(primary: String, explanation: String) -> FollowUpHint {
        FollowUpHint(
            text: "↩ New line · ⌘↩ \(primary)",
            help: "In a code block, Return adds a line and Tab / ⇧Tab indent.\n⌘Return: \(explanation)")
    }
}
