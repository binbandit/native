/// Why the composer can't send right now, so it can say so instead of doing nothing
/// (docs/product-quality.md).
/// A session that is still loading isn't blocked: what's sent waits in the queue until it's ready.
enum SendBlocker: Equatable {
    case disconnected(agentName: String)
    /// An agent's own subagent, which only takes work from its parent.
    case notAcceptingPrompts

    init?(phase: SessionModel.Phase, acceptsPrompts: Bool, agentName: String) {
        if !acceptsPrompts {
            self = .notAcceptingPrompts
        } else if phase == .disconnected {
            self = .disconnected(agentName: agentName)
        } else {
            return nil
        }
    }

    var message: String {
        switch self {
        case .disconnected(let agentName): "Can’t send: \(agentName) stopped running. Restart it from the sidebar."
        case .notAcceptingPrompts: "This subagent only takes work from the session that started it"
        }
    }
}
