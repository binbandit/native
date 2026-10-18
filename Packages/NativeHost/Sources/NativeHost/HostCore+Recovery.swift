import ACP
import Foundation
import NativeHostProtocol

// Recovery: finishing turns that an agent crash, a host crash or a restart of the Mac cut off. The
// session is reloaded from the agent's store, and `RecoveryPlanner` decides from its replay whether
// to send the prompt again or tell the agent it was interrupted. Tool calls are never re-run.
extension HostCore {
    /// At startup: every turn the previous run left unfinished is recovered, and queues that were
    /// waiting on a turn start draining once their session is back.
    func resumeInterruptedWork() throws {
        let previousBoot = try store.meta(MetaKey.bootTime).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        let lastSeenAlive = try store.meta(MetaKey.heartbeat).flatMap(Double.init).map(
            Date.init(timeIntervalSince1970:))
        let wasUpdate = try store.meta(MetaKey.restartReason) == "update"
        let cause =
            wasUpdate
            ? .hostUpdated : RecoveryPlanner.cause(previousBoot: previousBoot, currentBoot: configuration.bootTime)
        try store.setMeta(MetaKey.restartReason, nil)
        try store.setMeta(MetaKey.bootTime, configuration.bootTime.map { String($0.timeIntervalSince1970) })
        try store.setMeta(MetaKey.cleanShutdown, "0")

        // Approvals that were waiting died with the old agent processes; agents ask again on resume.
        for (sessionID, _) in try store.approvals() {
            try store.removeApprovals(sessionID: sessionID)
        }
        let turns = try store.unfinishedTurns()
        if !turns.isEmpty {
            journal(
                .hostStarted, session: nil,
                detail: "Resuming \(turns.count) interrupted \(turns.count == 1 ? "task" : "tasks")")
        }
        for turn in turns {
            guard let session = sessions[turn.sessionID] else {
                try store.finishTurn(turn.sessionID)
                continue
            }
            session.turn = turn
            session.phase = .recovering
            // The host's last heartbeat dates the interruption to within one interval.
            let interruptedAt = max(lastSeenAlive ?? turn.startedAt, turn.startedAt)
            Task { await recover(session, cause: cause, interruptedAt: interruptedAt) }
        }
        for session in sessions.values
        where session.turn == nil && !session.queue.isEmpty && !session.record.isQueuePaused {
            Task {
                try? await load(session)
                drainQueue(session)
            }
        }
    }

    /// An agent process went away. Sessions that were mid-turn are recovered on a new process;
    /// the others reload quietly the next time they're used.
    func agentExited(_ agentID: String, generation: Int) {
        guard let link = agents[agentID], link.noteExit(generation: generation) else { return }
        let wasStopped = link.status == .stopped
        let now = Date.now
        for session in sessions.values where session.record.agentID == agentID {
            if session.record.origin == .announced {
                // A subagent lives in its parent's agent process; the parent's reload brings it back.
                sessions[session.id] = nil
                continue
            }
            session.needsLoad = true
            withdrawPermissions(of: session)
            guard session.turn != nil, !wasStopped else {
                publish(session)
                continue
            }
            session.phase = .recovering
            publish(session)
            Task { await recover(session, cause: .agentStopped, interruptedAt: now) }
        }
    }

    /// Brings one interrupted turn back: reloads the session, then resends or resumes.
    func recover(_ session: HostSession, cause: RecoveryNote.Cause, interruptedAt: Date) async {
        guard let turn = session.turn else { return }
        session.isRecoveryCancelled = false
        if turn.attempts >= RecoveryPlanner.maximumAttempts {
            conclude(
                turn, in: session,
                note: RecoveryNote(
                    cause: cause, action: .paused, agentName: session.agentName, interruptedAt: interruptedAt))
            return
        }
        do {
            try await load(session)
        } catch {
            guard !session.isRecoveryCancelled else { return }
            // The turn stays committed: it resumes when the agent can run again (the user's next
            // message, or the next time the host starts).
            session.phase = .disconnected
            let note = RecoveryNote(
                cause: cause, action: .failed, agentName: session.agentName, interruptedAt: interruptedAt,
                problem: error.localizedDescription)
            append(.recovered(note), to: session)
            journal(.recovered, session: session, recovery: note)
            publish(session)
            return
        }
        guard !session.isRecoveryCancelled, session.turn?.requestID == turn.requestID else { return }
        let decision = RecoveryPlanner.decide(
            prompt: turn.text, attempts: turn.attempts, replayedUserMessages: session.mirror.userMessages)
        let action: RecoveryNote.Action =
            switch decision {
            case .resend: .resent
            case .resume: .resumed
            case .pause: .paused
            }
        let note = RecoveryNote(
            cause: cause, action: action, agentName: session.agentName, interruptedAt: interruptedAt)
        if decision == .pause {
            conclude(turn, in: session, note: note)
            return
        }
        append(.recovered(note), to: session)
        journal(.recovered, session: session, recovery: note)
        let prompt =
            switch decision {
            case .resume:
                QueuedPrompt(text: RecoveryPlanner.interruptionPrompt(cause: cause), isEchoed: false)
            default:
                // The reload replaced the transcript, which no longer shows the message; echo it again.
                QueuedPrompt(id: turn.requestID, text: turn.text, isEchoed: true)
            }
        // Steered messages the agent recorded arrived; the rest wait their turn in the queue.
        let replayed = session.mirror.userMessages
        session.queue.removeAll {
            $0.isSteering && RecoveryPlanner.agentReceived($0.prompt.text, replayedUserMessages: replayed)
        }
        for index in session.queue.indices {
            session.queue[index].isSteering = false
        }
        do {
            try startTurn(
                in: session, prompt: prompt, origin: .user, kind: decision == .resume ? .recovery : turn.kind,
                attempts: turn.attempts + 1
            )
        } catch {
            logger.error("Couldn't restart an interrupted turn: \(error.localizedDescription)")
        }
    }

    /// Ends a turn recovery gave up on, pausing the queue so nothing piles onto a failing agent.
    private func conclude(_ turn: UnfinishedTurn, in session: HostSession, note: RecoveryNote) {
        endTurn(in: session, stopReason: "error", pauseQueue: true)
        append(.recovered(note), to: session)
        journal(.recovered, session: session, recovery: note)
        publish(session)
    }
}
