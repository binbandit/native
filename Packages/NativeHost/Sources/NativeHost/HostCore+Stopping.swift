import ACP
import Foundation
import NativeHostProtocol

// Stopping a turn, and sending again a prompt that failed for a passing reason. An agent that never
// confirms a stop would leave the user with no way out, so asking again, or the agent staying
// silent for `stopGracePeriod`, ends the turn on the host's side.
extension HostCore {
    /// How long the agent gets to confirm a stop before the host stops waiting for it.
    static let stopGracePeriod: Duration = .seconds(10)

    /// Stops what the session is doing: a retry waiting to go out, the running turn, or the recovery
    /// of one. The agent is asked to cancel; if it doesn't confirm within the grace period, or the
    /// user asks again more than a second later, the turn ends on the host's side.
    func cancel(_ session: HostSession) async {
        if session.retryAt != nil {
            cancelRetry(of: session)
            append(
                .notice(text: "Stopped retrying. Your message is still queued; send again to try it.", isError: false),
                to: session)
            publish(session)
            return
        }
        let link = agents[session.record.agentID]
        if session.record.origin == .announced, let peer = link?.peer,
            let agentSessionID = session.record.agentSessionID
        {
            // An agent's own subagent has no turn of its own; stopping it stops only its work.
            answerCancelled(session, on: peer)
            try? peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
            publish(session)
            return
        }
        guard let turn = session.turn else { return }
        guard session.phase == .prompting, let peer = link?.peer, let agentSessionID = session.record.agentSessionID
        else {
            // Nothing is running to cancel (the agent is being restarted); just let the turn go.
            session.isRecoveryCancelled = true
            finish(turn, in: session, stopReason: "cancelled")
            return
        }
        if let first = session.stopRequestedAt {
            // A second press, not a double click, means the user is done waiting for the agent.
            if Date.now.timeIntervalSince(first) > 1 {
                abandon(turn, in: session)
            }
            return
        }
        session.stopRequestedAt = .now
        session.stopTimeout = Task { [weak self, weak session] in
            try? await Task.sleep(for: Self.stopGracePeriod)
            guard !Task.isCancelled, let self, let session else { return }
            abandon(turn, in: session)
        }
        answerCancelled(session, on: peer)
        try? peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
        publish(session)
    }

    /// ACP requires answering open permission requests and questions as cancelled when a turn is
    /// cancelled.
    private func answerCancelled(_ session: HostSession, on peer: JSONRPCPeer) {
        for (_, requestID) in session.pendingPermissions {
            try? peer.respond(to: requestID, with: RequestPermissionResponse.cancelled)
        }
        withdrawPermissions(of: session)
        withdrawQuestions(of: session)
    }

    /// Ends a turn being stopped without the agent's word; its late answer is ignored.
    private func abandon(_ turn: UnfinishedTurn, in session: HostSession) {
        guard session.turn?.requestID == turn.requestID else { return }
        endTurn(in: session, stopReason: "cancelled", pauseQueue: true)
        append(.turnEnded(stopReason: "cancelled"), to: session)
        append(
            .notice(
                text:
                    "\(session.agentName) didn't confirm it stopped, so Native stopped waiting. It may still be finishing its last step.",
                isError: false), to: session)
        publish(session)
        continueAfterTurn(session)
    }

    // MARK: - Retrying

    func scheduleRetry(of session: HostSession, after delay: Duration) {
        session.retryAt = .now.addingTimeInterval(Double(delay.components.seconds))
        session.retryTask = Task { [weak self, weak session] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let session else { return }
            session.retryAt = nil
            session.retryTask = nil
            session.record.isQueuePaused = false
            drainQueue(session)
            publish(session)
        }
    }

    func cancelRetry(of session: HostSession) {
        session.retryTask?.cancel()
        session.retryTask = nil
        session.retryAt = nil
    }
}

/// When to send a failed prompt again: only when the failure looks like the network or the provider
/// being briefly unavailable, a few times, further apart each time. Usage limits and sign-in
/// problems are someone else's to handle.
enum TurnRetry {
    static let delays: [Duration] = [.seconds(5), .seconds(20), .seconds(60)]

    /// The wait before the next try, or nil to stop trying.
    static func delay(after error: any Error, attempts: Int) -> Duration? {
        guard isTransient(error), attempts < delays.count else { return nil }
        return delays[attempts]
    }

    static func isTransient(_ error: any Error) -> Bool {
        if (error as? RPCError)?.isAuthRequired == true || UsageLimitHit(error: error) != nil {
            return false
        }
        if error is URLError {
            return true
        }
        let text = error.localizedDescription.lowercased()
        return transientMarkers.contains { text.contains($0) }
    }

    /// How agents word network and provider outages in the errors they pass on.
    private static let transientMarkers = [
        "network", "connection error", "connection refused", "connection reset", "timed out", "timeout",
        "econnreset", "econnrefused", "enotfound", "eai_again", "socket hang up", "fetch failed",
        "overloaded", "service unavailable", "bad gateway", "temporarily unavailable", " 502", " 503", " 529",
    ]
}
