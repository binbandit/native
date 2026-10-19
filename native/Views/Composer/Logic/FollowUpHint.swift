/// What Return and ⌘Return do with a follow-up while the agent works, as docs/keyboard.md asks the
/// composer to show.
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

    init(preferred: FollowUpBehavior, supportsSteering: Bool, agentName: String) {
        if supportsSteering {
            text = "↩ \(preferred.title) · ⌘↩ \(preferred.opposite.title)"
            help = "Return: \(preferred.explanation)\n⌘Return: \(preferred.opposite.explanation)"
        } else {
            text = "↩ Queue · Steering unavailable"
            help = "\(agentName) can’t add a message to a turn in progress, so ⌘↩ queues it too."
        }
    }
}
