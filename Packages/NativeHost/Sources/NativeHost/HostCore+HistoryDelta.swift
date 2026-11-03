import ACP
import Foundation
import NativeHostProtocol

/// A delta about to go with a returning session's message: which transfer it is, and what the
/// budgeted handoff chose for it.
struct HistoryDeltaDelivery {
    let transfer: UUID
    let through: Int
    let conveyed: [ClosedRange<Int>]
    let receipt: ContextTransfer.Receipt
}

// Switching back with a delta (docs/decisions/2026-11-01-one-task-history.md): a change of agent that
// returns to a conversation the task already had prepares a `delta` transfer of what it missed, and
// the host renders it when the conversation's next message starts its turn, so it covers everything
// up to that moment. Selection and rendering are the budgeted handoff's (`ContextTransferSelector`).
extension HostCore {
    /// The returning session's prepared delta, unless one is already waiting or on its way with the
    /// running turn. Nothing when it has missed nothing.
    func prepareDelta(
        for participant: TaskHistoryParticipant, of session: HostSession, in history: TaskHistoryID
    )
        throws
    {
        var transfers = try store.historyTransfers(of: history).filter {
            $0.target == participant.ordinal && $0.sourceHistory == history
        }
        // A handoff bound to a message that's gone (removed from the queue) was abandoned; it gives way
        // to the delta, which covers everything the conversation is missing, its items included.
        let queued = Set(session.queue.map(\.prompt.id))
        let abandoned = transfers.filter {
            $0.state == .prepared && $0.strategy == .client && $0.requestID.map { !queued.contains($0) } ?? false
        }
        guard
            !transfers.contains(where: {
                ($0.state == .prepared && !abandoned.contains($0))
                    || ($0.state == .sent && $0.requestID == session.turn?.requestID)
            })
        else { return }
        if !abandoned.isEmpty {
            try store.supersedePreparedTransfers(in: history, to: participant.ordinal)
            transfers = try store.historyTransfers(of: history).filter {
                $0.target == participant.ordinal && $0.sourceHistory == history
            }
        }
        let missing = try missingItems(of: participant, in: history, transfers: transfers)
        guard let head = try store.historyHead(history), !missing.isEmpty else { return }
        try store.insertTransfer(
            TaskHistoryTransfer(
                sourceHistory: history, target: participant.ordinal, from: participant.seen, through: head,
                conveyed: [], strategy: .delta), into: history)
    }

    /// A change of agent that returned to `params.sessionID` was undone: the context it prepared
    /// for the session's next message won't go.
    func withdrawHistory(_ params: SessionParams) throws -> TaskHistorySummary {
        let session = try session(params.sessionID)
        guard let history = try history(of: session) else { throw HostError.noHistory }
        try store.supersedePreparedTransfers(in: history.id, to: history.participant)
        return try historySummary(params)
    }

    /// The client's handoff goes with the session's message `requestID`: what its receipt carried of
    /// the items the handoff considered counts as seen once the agent answers that message (or now,
    /// if it already has). A message still queued binds the handoff to it, so no other turn delivers it.
    func recordHandoff(_ params: HandoffHistoryParams) throws -> TaskHistorySummary {
        let session = try session(params.sessionID)
        guard let history = try history(of: session) else { throw HostError.noHistory }
        try store.transaction {
            guard TaskHistoryDelta.namesHistory(params.receipt),
                let handoff = try store.historyTransfers(of: history.id).last(where: {
                    $0.target == history.participant && $0.strategy == .client
                        && ($0.requestID == params.requestID || ($0.state == .prepared && $0.requestID == nil))
                })
            else { return }
            let considered = try store.historyItems(
                of: history.id, after: handoff.from, through: handoff.through, limit: .max
            ).filter { $0.source != history.participant }
            try store.setTransferCoverage(
                handoff.id, conveyed: TaskHistoryDelta.covered(by: params.receipt, items: considered),
                receipt: params.receipt, requestID: params.requestID)
            if handoff.state == .delivered { try store.updateWatermark(of: history.participant, in: history.id) }
        }
        return try historySummary(SessionParams(sessionID: session.id))
    }

    /// `prompt` with the session's prepared delta ahead of it, chosen now so it covers everything
    /// up to this message. Nil when there's no delta to send.
    func renderDelta(
        for prompt: OutgoingPrompt, in session: HostSession, history: HostSessionHistory
    ) throws -> (OutgoingPrompt, HistoryDeltaDelivery)? {
        let transfers = try store.historyTransfers(of: history.id)
        guard
            let transfer = transfers.first(where: {
                $0.target == history.participant && $0.strategy == .delta && $0.state == .prepared
            })
        else { return nil }
        let participants = try store.historyParticipants(of: history.id)
        guard let participant = participants.first(where: { $0.ordinal == history.participant }),
            let head = try store.historyHead(history.id)
        else { return nil }
        let missing = try missingItems(of: participant, in: history.id, transfers: transfers)
        let blocks = prompt.content ?? [.text(prompt.text)]
        let usage = session.mirror.state.usage
        let capabilities = EffectiveAgentCapabilities(
            negotiated: agents[session.record.agentID]?.capabilities,
            options: session.mirror.state.configOptions)
        let context = ContextTransfer(
            draft: TaskHistoryDelta.draft(missing, participants: participants),
            destination: .init(agent: participant.agentID, session: participant.agentSessionID),
            model: participant.model,
            plan: AgentTransitionPlan.resolve(.reuse, target: capabilities, sameSession: true),
            budget: .init(windowTokens: usage?.size, usedTokens: usage?.used ?? 0, prompt: blocks))
        var sent = prompt
        // The handoff's frame, under this transfer's own marker, so a transcript can find it again.
        if let text = ContextTransferSelector.block(for: context)?.text, let frame = PromptPreamble(framed: text) {
            let preamble = PromptPreamble(
                marker: .init(id: transfer.markerID, label: frame.marker.label, symbol: frame.marker.symbol),
                instructions: frame.instructions)
            sent.content = [preamble.block] + blocks
        }
        return (
            sent,
            HistoryDeltaDelivery(
                transfer: transfer.id, through: head,
                conveyed: TaskHistoryDelta.covered(by: context.receipt, items: missing),
                receipt: context.receipt)
        )
    }

    /// The items above the participant's watermark it neither produced nor was given.
    private func missingItems(
        of participant: TaskHistoryParticipant, in history: TaskHistoryID, transfers: [TaskHistoryTransfer]
    ) throws -> [TaskHistoryItem] {
        TaskHistoryCoverage.missing(
            try store.historyItems(of: history, after: participant.seen, limit: .max),
            participant: participant.ordinal,
            conveyed: TaskHistoryCoverage.conveyed(to: participant.ordinal, by: transfers, in: history))
    }
}
