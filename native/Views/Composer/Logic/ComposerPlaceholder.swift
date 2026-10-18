/// What the empty composer says: what typing will do (start work, queue or steer a follow-up), or
/// why it can't yet.
struct ComposerPlaceholder {
    var phase: SessionModel.Phase
    var agentName: String
    var hasQuestion: Bool
    var needsApproval: Bool
    var followUp: FollowUpBehavior
    var supportsSteering: Bool
    var isNewSession: Bool
    /// Adds how to get back to the composer without the mouse.
    var showsFocusHint: Bool

    var text: String {
        let agent = agentName
        let text =
            switch phase {
            case .loading: "Loading… messages send when \(agent) is ready"
            case .disconnected: "\(agent) isn’t running"
            case .prompting where hasQuestion: "\(agent) is waiting for your answer above…"
            case .prompting where needsApproval: "\(agent) is waiting for your approval…"
            case .prompting where followUp == .steer && supportsSteering: "Steer \(agent)’s current turn…"
            case .prompting: "Queue a follow-up for \(agent)…"
            case .idle where isNewSession: "What would you like \(agent) to work on?"
            case .idle: "Message \(agent), or type / for commands"
            }
        return showsFocusHint ? "\(text)  ⌘L to focus" : text
    }
}
