/// Why the composer can't send right now, so it can say so instead of doing nothing
/// (docs/product-quality.md).
enum SendBlocker: Equatable {
    case loading
    case disconnected(agentName: String)
    /// An agent's own subagent, which only takes work from its parent.
    case notAcceptingPrompts

    init?(phase: SessionModel.Phase, acceptsPrompts: Bool, agentName: String) {
        if !acceptsPrompts {
            self = .notAcceptingPrompts
        } else if phase == .loading {
            self = .loading
        } else if phase == .disconnected {
            self = .disconnected(agentName: agentName)
        } else {
            return nil
        }
    }

    var message: String {
        switch self {
        case .loading: "Can’t send yet: the session is still loading"
        case .disconnected(let agentName): "Can’t send: \(agentName) stopped running. Restart it from the sidebar."
        case .notAcceptingPrompts: "This subagent only takes work from the session that started it"
        }
    }
}
