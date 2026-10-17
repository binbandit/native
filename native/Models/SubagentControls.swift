import ACP

/// What a parent may currently do about its subagents: which need the user and which can be
/// cancelled. Only reports made while the session is live count. Replayed history can't vouch for
/// either (the subagents RFD), so a loaded session starts with none until the agent reports afresh.
nonisolated struct SubagentControls: Equatable, Sendable {
    private var workStates: [SessionID: SubagentWorkState] = [:]
    private var cancellable: Set<SessionID> = []

    var isAnyWaitingOnUser: Bool {
        workStates.values.contains(.requiresAction)
    }

    func canCancel(_ subagent: SessionID) -> Bool {
        cancellable.contains(subagent)
    }

    mutating func apply(_ update: SubagentUpdate) {
        switch update.state {
        case .unchanged: break
        case .cleared: workStates[update.sessionId] = nil
        case .set(let workState): workStates[update.sessionId] = workState
        }
        switch update.canCancel {
        case .unchanged: break
        case .set(true): cancellable.insert(update.sessionId)
        case .set(false), .cleared: cancellable.remove(update.sessionId)
        }
    }

    /// Forgets everything, for when the connection is lost and nothing reported is current.
    mutating func reset() {
        self = SubagentControls()
    }
}
