import ACP
import Foundation
import NativeHostProtocol

// Stopping a turn, and sending again a prompt that failed for a passing reason. ACP cancellation
// can return while shell commands still run, so only verified process exit ends a stopped turn.
extension HostCore {
    static let stopGracePeriod: TimeInterval = 2

    /// Stops what the session is doing: a retry waiting to go out, the running turn, or the recovery
    /// of one. Cancellation gets a short grace period before Native ends the owned process tree.
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
            append(
                .notice(
                    text:
                        "Commands may still be running. Stop the parent task to verify that its subagent's commands have ended.",
                    isError: true),
                to: session)
            publish(session)
            return
        }
        guard let turn = session.turn else { return }
        session.isRecoveryCancelled = true
        if let first = session.stopRequestedAt {
            // A second press skips the grace period, never the process-exit check.
            if Date.now.timeIntervalSince(first) > 1 {
                session.stopRequestedAt = .distantPast
            }
            return
        }
        guard let link, let processes = link.processesForStop() else {
            // No launched generation remains to cancel while the agent is being restarted.
            finish(turn, in: session, stopReason: "cancelled")
            return
        }
        session.stopRequestedAt = .now
        link.commandStopOwnsTree = true
        let generation = link.generation
        session.stopTimeout = Task { [weak self] in
            await self?.endStoppedCommands(turn, in: session, on: link, generation: generation, processes: processes)
        }
        if let peer = link.peer, let agentSessionID = session.record.agentSessionID {
            answerCancelled(session, on: peer)
            try? peer.notify("session/cancel", CancelNotification(sessionId: agentSessionID))
        }
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
