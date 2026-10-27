import NativeHostClient
import NativeHostProtocol

extension DurableHost {
    /// Only this channel's local host is eligible, including its session-only fallback. Paired
    /// hosts and agents running in the app must never be substituted for it.
    var canRequestHostRestart: Bool {
        placement.usesHost && client != nil && manualRestart.state != .restarting
    }

    /// The same visible task names in the waiting row and the interruption confirmation.
    func interruptedTaskNames(in model: AppModel) -> [String] {
        interruptedByRestart.map { summary in
            let listed = summary.agentSessionID.flatMap { id in
                let key = SessionKey(agent: AgentDefinition.ID(rawValue: summary.agentID), id: id)
                return model.sessionList.first { $0.id == key }
            }
            return listed.map(model.title(for:)) ?? summary.title ?? "New Task"
        }
    }

    func requestHostRestart() {
        guard canRequestHostRestart else { return }
        manualRestart.request()
    }

    func cancelHostRestart() {
        manualRestart.cancel()
    }

    func confirmHostRestart(whenIdle: Bool = false) async {
        guard placement.usesHost, let client else {
            manualRestart.cancel()
            return
        }
        await manualRestart.restart(using: client, whenIdle: whenIdle)
    }
}
