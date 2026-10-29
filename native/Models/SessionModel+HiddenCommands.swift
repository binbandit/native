import ACP

extension SessionModel {
    /// Runs a command such as `/context` as a turn the transcript doesn't show, and returns the
    /// agent's reply. Meanwhile the session stays idle to the eye, but new messages queue and
    /// queued ones wait. Throws unless the session is idle, or if the turn fails.
    func runHiddenCommand(_ command: String) async throws -> String {
        guard acceptsPrompts else { throw SendError.notAcceptingPrompts }
        switch phase {
        case .loading: throw SendError.loading
        case .disconnected: throw SendError.disconnected
        case .prompting: throw SendError.busy
        case .idle where isRunningHiddenCommand || isDeliveringSteer: throw SendError.busy
        case .idle: break
        }
        if host != nil {
            // The host keeps the reply out of the transcript and holds the queue meanwhile.
            return try await runHiddenCommandOnHost(command)
        }
        guard let connection else { throw SendError.disconnected }
        hiddenCommand = HiddenCommandCapture()
        isRunningHiddenCommand = true
        defer {
            hiddenCommandEcho = hiddenCommand
            hiddenCommand = nil
            isRunningHiddenCommand = false
            drainQueue()
        }
        _ = try await connection.send(PromptRequest(sessionId: id, prompt: [.text(command)]))
        return hiddenCommand?.output ?? ""
    }
}
