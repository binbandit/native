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

    /// Records the message a turn starts with, inside the transaction that commits the turn, and
    /// sends the context prepared for the session with it. The participant's model follows the one the
    /// message goes to. A retry of the same request finds it recorded already.
    func recordPrompt(_ prompt: OutgoingPrompt, of session: HostSession, in history: HostSessionHistory) {
        do {
            if let model = session.mirror.state.configOptions.modelValue {
                try store.setHistoryModel(model, of: history.participant, in: history.id)
            }
            try store.sendHistoryTransfers(in: history.id, to: history.participant, with: prompt.id)
            guard try !store.hasHistoryItem(turn: prompt.id, in: history.id) else { return }
            let body = TaskHistoryRecording.user(
                prompt.text, attachments: prompt.attachments.map(\.name), origin: prompt.origin.rawValue)
            try store.appendHistoryItems(
                [body], to: history.id, source: history.participant, turn: prompt.id, at: .now)
        } catch {
            logger.error("Couldn't record a message in its task's history: \(error.localizedDescription)")
        }
    }

    /// Whether the turn's message waits for the session's load before it's recorded: a conversation
    /// whose history is still empty may have a replay to import first.
    func defersPromptRecording(_ session: HostSession, in history: HostSessionHistory) -> Bool {
        session.needsLoad && session.phase != .recovering && (try? store.historyHead(history.id)) == 0
    }

    /// Records a message `startTurn` deferred until its session loaded.
    func recordPromptAfterLoad(_ prompt: OutgoingPrompt, in session: HostSession) {
        guard let history = recordableHistory(of: session) else { return }
        do {
            try store.transaction { recordPrompt(prompt, of: session, in: history) }
        } catch {
            logger.error("Couldn't record a message in its task's history: \(error.localizedDescription)")
        }
    }

    /// Records what the running turn did once it ends: its items after the message, settled as the
    /// ending event will settle them, the plan if it changed, and how it ended.
    func recordTurnEnd(of session: HostSession, stopReason: String) {
        guard let turn = session.turn else { return }
        // A message whose recording waited for a load that never finished (stopped, or failed) is
        // still recorded, before how its turn ended.
        recordPromptAfterLoad(turn.prompt, in: session)
        let items = session.historyTurnStart.map {
            Self.settledItems(session.mirror.state, from: $0, ending: stopReason)
        }
        record(items ?? [], of: turn.requestID, ending: stopReason, in: session)
    }

    /// A turn's items as its ending leaves them: a call still open when the user stopped it is
    /// `cancelled`, not `in_progress`, as the transcript shows it once the ending event lands.
    nonisolated static func settledItems(
        _ state: SessionState, from start: Int, ending stopReason: String
    ) -> [TranscriptItem] {
        var state = state
        state.endTurn(SessionMirror.stopReason(stopReason))
        return Array(state.items.dropFirst(start))
    }

    /// Before recovery tells the agent its turn was interrupted: what the agent's replay shows it did
    /// after the interrupted message, which the turn that follows wouldn't otherwise include.
    func recordInterrupted(_ turn: UnfinishedTurn, in session: HostSession) {
        let items = session.mirror.state.items
        guard let work = Self.interruptedWork(of: turn.text, in: items) else { return }
        // The message's text can match an older one; its frame says which context went with it.
        let shown = items[..<work.startIndex].suffix(2).compactMap { item -> String? in
            if case .message(let message) = item, message.role == .user { message.preamble?.id } else { nil }
        }
        record(Array(work), of: turn.requestID, ending: "interrupted", in: session, shownMarkers: Set(shown))
    }

    /// What follows the interrupted message in a replay. The message is found as it was sent, so a
    /// later steer that quotes it can't move the boundary past earlier work; a recovery prompt
    /// replays as Native's notice rather than a user message.
    nonisolated static func interruptedWork(
        of prompt: String, in items: [TranscriptItem]
    ) -> ArraySlice<TranscriptItem>? {
        func sent(_ item: TranscriptItem) -> String? {
            switch item {
            case .message(let message) where message.role == .user: message.text
            case .notice(let notice): notice.sentToAgent
            default: nil
            }
        }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let index = items.lastIndex(where: { sent($0)?.trimmingCharacters(in: .whitespacesAndNewlines) == text })
                ?? items.firstIndex(where: { item in
                    sent(item).map { RecoveryPlanner.agentReceived(prompt, replayedUserMessages: [$0]) } ?? false
                })
        else { return nil }
        return items[(index + 1)...]
    }

    /// `shownMarkers` are the context markers a replay shows the message went with; nil when the agent
    /// answered the message itself, which is evidence enough.
    private func record(
        _ items: [TranscriptItem], of turn: UUID, ending stopReason: String, in session: HostSession,
        shownMarkers: Set<String>? = nil
    ) {
        var bodies = TaskHistoryRecording.bodies(items)
        // Failing before the agent did anything leaves only the message: a retry or the user's next
        // message carries on from it.
        guard stopReason != "error" || !bodies.isEmpty, let history = recordableHistory(of: session) else { return }
        // A turn stopped before the agent said or did anything may never have reached it, so the
        // context that went with its message stays sent rather than counted as seen.
        let answered = !bodies.isEmpty || stopReason != "cancelled"
        do {
            try store.transaction {
                // A turn recorded already (a recovery finding a stopped turn in the replay) keeps its
                // items, but the replay is still evidence its context arrived.
                if try !store.hasHistoryItem(turn: turn, kind: "turn_ended", in: history.id) {
                    if let plan = TaskHistoryRecording.plan(session.mirror.state.plan),
                        try store.lastHistoryBody(kind: "plan", in: history.id) != plan
                    {
                        bodies.append(plan)
                    }
                    bodies.append(.turnEnded(stopReason: stopReason))
                    try store.appendHistoryItems(
                        bodies, to: history.id, source: history.participant, turn: turn, at: .now)
                }
                let deltas = try store.historyTransfers(of: history.id).filter {
                    $0.target == history.participant && $0.strategy == .delta && $0.state == .sent
                        && $0.requestID == turn
                }
                if answered {
                    // A delta its replay doesn't show goes again with the next message.
                    let unshown = deltas.filter { delta in
                        shownMarkers.map { !$0.contains(delta.markerID) } ?? false
                    }
                    try store.reprepareTransfers(unshown.map(\.id))
                    try store.deliverHistoryTransfers(in: history.id, to: history.participant, with: turn)
                } else {
                    // Stopped before the agent answered: a delta goes again with the next message. A
                    // client's handoff, which the host can't send again, stays sent.
                    try store.reprepareTransfers(deltas.map(\.id))
                }
            }
        } catch {
            logger.error("Couldn't record a turn in its task's history: \(error.localizedDescription)")
        }
    }

    /// A conversation from before its task had a history (opened from the agent's list, or open when
    /// the host was updated) brings its replay in once, without times or turns. A message sent before
    /// the replay waits to be recorded until after it (`recordPromptAfterLoad`), so the old
    /// conversation comes first. If that first load never completes (the turn is stopped, or the host
    /// stops and recovers it), the message is recorded anyway and the history starts with it: items
    /// are never renumbered, and the agent still has the earlier conversation for its own replay.
    func importHistory(of session: HostSession) {
        let items = session.mirror.state.items
        guard session.phase != .recovering, !items.isEmpty, let history = recordableHistory(of: session) else {
            return
        }
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

    /// A change of agent committed: the target's agent session joins the source's task history, and
    /// the client's handoff is recorded as a `client` transfer of what the target hadn't seen, crediting
    /// only the items the client says it conveyed. A target already in that history is returning, and
    /// gets a `delta` of what it missed instead, which the host renders with its next message.
    func joinHistory(_ params: JoinHistoryParams) throws -> TaskHistorySummary {
        let target = try session(params.sessionID)
        guard
            let source = try sourceHistory(agentID: params.sourceAgentID, agentSessionID: params.sourceAgentSessionID),
            target.record.origin != .announced, let agentSessionID = target.record.agentSessionID
        else { throw HostError.noHistory }
        let participant: TaskHistoryParticipant = try store.transaction {
            // A conversation the task already had is returning: it gets what it missed, once. That
            // also makes a repeated join (a client retrying after a lost reply) record nothing more.
            if let (current, joined) = try store.historyParticipant(
                agentID: target.record.agentID, agentSessionID: agentSessionID), current == source.id
            {
                try prepareDelta(for: joined, of: target, in: current)
                return joined
            }
            guard
                let joined = try store.joinHistory(
                    source.id, agentID: target.record.agentID, agentSessionID: agentSessionID,
                    model: target.mirror.state.configOptions.modelValue)
            else { throw HostError.busy("This conversation already has a history of its own.") }
            if let head = try store.historyHead(source.id), joined.seen < head {
                let considered = (joined.seen + 1)...head
                try store.insertTransfer(
                    TaskHistoryTransfer(
                        sourceHistory: source.id, target: joined.ordinal, from: joined.seen, through: head,
                        conveyed: params.conveyed.filter { $0.overlaps(considered) }.map { $0.clamped(to: considered) },
                        strategy: .client), into: source.id, receipt: params.receipt)
            }
            return joined
        }
        target.history = HostSessionHistory(id: source.id, participant: participant.ordinal)
        return try historySummary(SessionParams(sessionID: target.id))
    }

    /// The history of the conversation a change of agent continues from: through its open session,
    /// which starts the history if it has none yet, or through its participant once it has closed.
    private func sourceHistory(agentID: String, agentSessionID: SessionID) throws -> HostSessionHistory? {
        if let open = sessions.values.first(where: {
            $0.record.agentID == agentID && $0.record.agentSessionID == agentSessionID
        }) {
            return try history(of: open)
        }
        return try store.historyParticipant(agentID: agentID, agentSessionID: agentSessionID).map {
            HostSessionHistory(id: $0.0, participant: $0.1.ordinal)
        }
    }

    func missingHistory(_ params: SessionParams) throws -> TaskHistoryMissing {
        let session = try session(params.sessionID)
        guard let history = try history(of: session), let head = try store.historyHead(history.id),
            let participant = try store.historyParticipants(of: history.id).first(where: {
                $0.ordinal == history.participant
            })
        else { throw HostError.noHistory }
        let conveyed = TaskHistoryCoverage.conveyed(
            to: participant.ordinal, by: try store.historyTransfers(of: history.id), in: history.id)
        let missing = TaskHistoryCoverage.missing(
            try store.historyItems(of: history.id, after: participant.seen, limit: .max),
            participant: participant.ordinal, conveyed: conveyed)
        return TaskHistoryMissing(
            seen: participant.seen, head: head, items: Array(missing.suffix(500)), omitted: max(missing.count - 500, 0))
    }

    func historySummary(_ params: SessionParams) throws -> TaskHistorySummary {
        let session = try session(params.sessionID)
        guard let history = try history(of: session), let head = try store.historyHead(history.id) else {
            throw HostError.noHistory
        }
        return TaskHistorySummary(
            id: history.id, head: head, participants: try store.historyParticipants(of: history.id),
            current: history.participant, transfers: try store.historyTransfers(of: history.id))
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
