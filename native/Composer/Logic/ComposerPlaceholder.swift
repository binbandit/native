/// A plain message prompt, or what the session needs before work can continue.
struct ComposerPlaceholder {
    var phase: SessionModel.Phase
    var agentName: String
    var hasQuestion: Bool
    var needsApproval: Bool
    /// Stop was pressed and the agent hasn't ended the turn yet.
    var isStopping = false
    var isNewSession: Bool
    /// Adds how to get back to the composer without the mouse.
    var showsFocusHint: Bool

    var text: String {
        let agent = agentName
        let text =
            switch phase {
            case .loading: "Loading… messages send when \(agent) is ready"
            case .disconnected: "\(agent) isn’t running"
            case .prompting where isStopping: "Stopping \(agent)… waiting for commands to end"
            case .prompting where hasQuestion: "\(agent) is waiting for your answer above…"
            case .prompting where needsApproval: "\(agent) is waiting for your approval…"
            case .idle where isNewSession: "What would you like \(agent) to work on?"
            case .idle, .prompting: "Message \(agent), or type / for commands"
            }
        return showsFocusHint ? "\(text)  ⌘L to focus" : text
    }
}
