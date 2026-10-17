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
        case .idle where isRunningHiddenCommand: throw SendError.busy
        case .idle: break
        }
        hiddenCommand = HiddenCommandCapture()
        isRunningHiddenCommand = true
        defer {
            hiddenCommand = nil
            isRunningHiddenCommand = false
            drainQueue()
        }
        _ = try await connection.send(PromptRequest(sessionId: id, prompt: [.text(command)]))
        return hiddenCommand?.output ?? ""
    }
}
