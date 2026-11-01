import ACP
import Foundation
import NativeHostProtocol

/// Where a session's task history is, and the session's place in it.
struct HostSessionHistory: Hashable {
    let id: TaskHistoryID
    let participant: Int
}

// One task history (docs/decisions/2026-11-01-one-task-history.md): finding a session's history and
// reading it. A history starts the first time something needs it, so an agent session that never
// gets a message (a change of agent that was cancelled) leaves nothing behind.
extension HostCore {
    /// The session's task history, found through its agent session or started now. Nil for an
    /// announced subagent, whose parent's history covers its work, and before the agent session exists.
    func history(of session: HostSession) throws -> HostSessionHistory? {
        if let history = session.history { return history }
        guard session.record.origin != .announced, let agentSessionID = session.record.agentSessionID else {
            return nil
        }
        let agentID = session.record.agentID
        let (id, participant) =
            try store.historyParticipant(agentID: agentID, agentSessionID: agentSessionID)
            ?? store.transaction {
                try store.createHistory(
                    cwd: session.record.cwd, agentID: agentID, agentSessionID: agentSessionID,
                    model: session.mirror.state.configOptions.modelValue)
            }
        let history = HostSessionHistory(id: id, participant: participant.ordinal)
        session.history = history
        return history
    }

    func historySummary(_ params: SessionParams) throws -> TaskHistorySummary {
        let session = try session(params.sessionID)
        guard let history = try history(of: session), let head = try store.historyHead(history.id) else {
            throw HostError.noHistory
        }
        return TaskHistorySummary(
            id: history.id, head: head, participants: try store.historyParticipants(of: history.id),
            current: history.participant)
    }

    func readHistory(_ params: ReadHistoryParams) throws -> [TaskHistoryItem] {
        let session = try session(params.sessionID)
        guard let history = try history(of: session) else { throw HostError.noHistory }
        return try store.historyItems(
            of: history.id, after: max(params.after, 0), through: params.through, limit: min(max(params.limit, 0), 500))
    }
}

extension [ConfigOption] {
    /// The model the options say is selected, by its value.
    fileprivate var modelValue: String? {
        guard case .select(let value, _)? = first(where: { $0.category == "model" })?.kind else { return nil }
        return value
    }
}
