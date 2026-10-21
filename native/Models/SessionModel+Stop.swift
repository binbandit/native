import ACP
import Foundation

// The host verifies command exit. The in-app fallback cannot prove that a cancel reply ended the
// agent's shell commands, so it keeps the turn stopping and explains that limit.
extension SessionModel {
    static let stopGracePeriod: Duration = .seconds(2)

    /// Cancels the current turn. For a subagent, that stops only its work, never its parent's turn.
    func cancel() async {
        guard canCancel else { return }
        // The host keeps the stop's grace period and retries itself, so they work with the app closed.
        if host != nil {
            return await cancelOnHost()
        }
        if isRetryScheduled {
            cancelRetry()
            state.appendNotice("Stopped retrying. Your message is still queued; send again to try it.", isError: false)
            return
        }
        if isStopping {
            // A repeated press explains why Native cannot yet confirm the stop.
            if let first = stopRequestedAt, Date.now.timeIntervalSince(first) > 1 {
                explainUnconfirmedStop()
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
                explainUnconfirmedStop()
            }
        }
        // ACP requires answering open permission requests as cancelled when a turn is cancelled.
        for (toolCallID, _) in state.pendingPermissions {
            guard let permission = state.resolvePermission(toolCallID: toolCallID) else { continue }
            if NativeApprovals.isNative(permission.requestID) {
                NativeApprovals.answer(permission.requestID, with: nil)
            } else {
                try? await connection?.respond(to: permission.requestID, with: RequestPermissionResponse.cancelled)
            }
        }
        await cancelQuestions()
        try? await connection?.notify(CancelNotification(sessionId: id))
    }

    /// An acknowledgement alone is not evidence that commands ended. Keep the running state so
    /// the sidebar and status bar cannot claim that all work stopped.
    func explainUnconfirmedStop() {
        guard phase == .prompting else { return }
        let message =
            "Commands may still be running. Native cannot verify this stop in this session. Check the running command before continuing."
        guard
            !state.items.contains(where: {
                if case .notice(let notice) = $0 { return notice.text == message }
                return false
            })
        else { return }
        state.appendNotice(message, isError: true)
    }

    /// Clears the stop once the turn is over, whoever ended it.
    func finishStopping() {
        stopTimeout?.cancel()
        stopTimeout = nil
        stopRequestedAt = nil
        isStopping = false
    }
}
