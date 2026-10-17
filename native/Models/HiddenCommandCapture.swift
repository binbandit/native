import ACP

/// Collects the agent's reply to a command run outside the transcript (see
/// `SessionModel.runHiddenCommand`).
nonisolated struct HiddenCommandCapture: Sendable {
    private(set) var output = ""

    /// Takes the update if it's part of the reply, reporting whether it did. Everything else (usage,
    /// tool calls) still belongs to the session.
    mutating func capture(_ update: SessionUpdate) -> Bool {
        guard case .agentMessageChunk(let chunk) = update else { return false }
        output += chunk.content.text ?? ""
        return true
    }
}
