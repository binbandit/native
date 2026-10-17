/// What Return and ⌘Return do with a follow-up while the agent works, as docs/keyboard.md asks the
/// composer to show.
struct FollowUpHint: Equatable {
    let text: String
    let help: String

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
