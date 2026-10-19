import ACP
import Foundation

// Stopping a turn. Native asks the agent to cancel (`session/cancel`) and the agent ends the turn
// as stopped. An agent that never confirms would leave the user with no way out, so pressing Stop
// again, or the agent staying silent for `stopGracePeriod`, ends the turn on Native's side.
extension SessionModel {
    /// How long the agent gets to confirm a stop before Native stops waiting for it.
    static let stopGracePeriod: Duration = .seconds(10)

    /// Cancels the current turn. For a subagent, that stops only its work, never its parent's turn.
    func cancel() async {
        guard canCancel else { return }
        if isRetryScheduled {
            cancelRetry()
            state.appendNotice("Stopped retrying. Your message is still queued; send again to try it.", isError: false)
            return
        }
        if isStopping {
            // A second press, not a double click, means the user is done waiting for the agent.
            if let first = stopRequestedAt, Date.now.timeIntervalSince(first) > 1 {
                abandonTurn()
            }
            return
        }
        if phase == .prompting {
            isStopping = true
            stopRequestedAt = .now
            let generation = turnGeneration
            stopTimeout = Task { [weak self] in
                try? await Task.sleep(for: Self.stopGracePeriod)
                guard !Task.isCancelled, let self, turnGeneration == generation else { return }
                abandonTurn()
            }
        }
        // ACP requires answering open permission requests as cancelled when a turn is cancelled.
        for (toolCallID, _) in state.pendingPermissions {
            guard let permission = state.resolvePermission(toolCallID: toolCallID) else { continue }
            if NativeApprovals.isNative(permission.requestID) {
                NativeApprovals.answer(permission.requestID, with: nil)
            } else {
                try? await connection.respond(to: permission.requestID, with: RequestPermissionResponse.cancelled)
            }
        }
        await cancelQuestions()
        try? await connection.notify(CancelNotification(sessionId: id))
    }

    /// Ends the turn being stopped without the agent's word. Its late answer, if one comes, is
    /// ignored: `turnDidEnd` moves `turnGeneration` past it.
    func abandonTurn() {
        guard phase == .prompting else { return }
        state.endTurn(.cancelled)
        state.appendNotice(
            "\(agentName) didn't confirm it stopped, so Native stopped waiting. It may still be finishing its last step.",
            isError: false)
        lastStopReason = .cancelled
        services.post(.turnEnded(context, .cancelled))
        phase = .idle
        turnDidEnd()
    }

    /// Clears the stop once the turn is over, whoever ended it.
    func finishStopping() {
        stopTimeout?.cancel()
        stopTimeout = nil
        stopRequestedAt = nil
        isStopping = false
    }
}
