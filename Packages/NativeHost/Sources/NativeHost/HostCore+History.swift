import ACP
import Foundation
import NativeHostProtocol

/// Where a session's task history is, and the session's place in it.
struct HostSessionHistory: Hashable {
    let id: TaskHistoryID
    let participant: Int
}

// One task history (docs/decisions/2026-11-01-one-task-history.md): finding a session's history,
// recording into it at the boundaries the store already writes at (a turn's start and end, a load),
// and reading it. A history starts the first time something needs it, so an agent session that never
// gets a message (a change of agent that was cancelled) leaves nothing behind. Recording is best
// effort: a turn never fails because its history couldn't be written.
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

    /// The session's history, for recording: a failure to find or start it is logged, not thrown.
    func recordableHistory(of session: HostSession) -> HostSessionHistory? {
        do {
            return try history(of: session)
        } catch {
            logger.error("Couldn't open a task's history: \(error.localizedDescription)")
            return nil
        }
    }

    /// Records the message a turn starts with, inside the transaction that commits the turn. A retry
    /// of the same request finds it recorded already.
    func recordPrompt(_ prompt: OutgoingPrompt, in history: HostSessionHistory) {
        do {
            guard try !store.hasHistoryItem(turn: prompt.id, in: history.id) else { return }
            let body = TaskHistoryRecording.user(
                prompt.text, attachments: prompt.attachments.map(\.name), origin: prompt.origin.rawValue)
            try store.appendHistoryItems(
                [body], to: history.id, source: history.participant, turn: prompt.id, at: .now)
        } catch {
            logger.error("Couldn't record a message in its task's history: \(error.localizedDescription)")
        }
    }

    /// Records what the running turn did once it ends: its items after the message, the plan if it
    /// changed, and how it ended.
    func recordTurnEnd(of session: HostSession, stopReason: String) {
        guard let turn = session.turn else { return }
        let items = session.historyTurnStart.map { Array(session.mirror.state.items.dropFirst($0)) } ?? []
        record(items, of: turn.requestID, ending: stopReason, in: session)
    }

    /// Before recovery tells the agent its turn was interrupted: what the agent's replay shows it did
    /// after the interrupted message, which the turn that follows wouldn't otherwise include.
    func recordInterrupted(_ turn: UnfinishedTurn, in session: HostSession) {
        let items = session.mirror.state.items
        guard
            let prompt = items.lastIndex(where: { item in
                guard case .message(let message) = item, message.role == .user else { return false }
                return RecoveryPlanner.agentReceived(turn.text, replayedUserMessages: [message.text])
            })
        else { return }
        record(Array(items[(prompt + 1)...]), of: turn.requestID, ending: "interrupted", in: session)
    }

    private func record(_ items: [TranscriptItem], of turn: UUID, ending stopReason: String, in session: HostSession) {
        var bodies = TaskHistoryRecording.bodies(items)
        // Failing before the agent did anything leaves only the message: a retry or the user's next
        // message carries on from it.
        guard stopReason != "error" || !bodies.isEmpty, let history = recordableHistory(of: session) else { return }
        do {
            try store.transaction {
                guard try !store.hasHistoryItem(turn: turn, kind: "turn_ended", in: history.id) else { return }
                if let plan = TaskHistoryRecording.plan(session.mirror.state.plan),
                    try store.lastHistoryBody(kind: "plan", in: history.id) != plan
                {
                    bodies.append(plan)
                }
                bodies.append(.turnEnded(stopReason: stopReason))
                try store.appendHistoryItems(
                    bodies, to: history.id, source: history.participant, turn: turn, at: .now)
            }
        } catch {
            logger.error("Couldn't record a turn in its task's history: \(error.localizedDescription)")
        }
    }

    /// A conversation from before its task had a history (opened from the agent's list, or open when
    /// the host was updated) brings its replay in once, without times or turns.
    func importHistory(of session: HostSession) {
        let items = session.mirror.state.items
        guard session.turn == nil, !items.isEmpty, let history = recordableHistory(of: session) else { return }
        do {
            try store.transaction {
                guard try store.historyHead(history.id) == 0 else { return }
                try store.appendHistoryItems(
                    TaskHistoryRecording.bodies(items), to: history.id, source: history.participant, turn: nil,
                    at: nil)
            }
        } catch {
            logger.error("Couldn't bring a conversation into its task's history: \(error.localizedDescription)")
        }
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
