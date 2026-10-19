import Foundation

/// Collects the agent's reply to a command a client runs outside the transcript (Native's
/// `/context` and `/usage` reads), and afterwards recognizes the reply's late copies.
///
/// claude-agent-acp 0.93.0 sends a local command's output twice, from two SDK message shapes, with
/// a few characters of whitespace between them, and the second can arrive after the turn has ended.
/// Arriving outside any turn, that copy would land in the transcript as a reply of its own.
public struct HiddenCommandCapture: Sendable {
    public private(set) var output = ""

    public init() {}

    /// Takes the update if it's part of the reply, reporting whether it did. Everything else (usage,
    /// tool calls) still belongs to the session.
    public mutating func capture(_ update: SessionUpdate) -> Bool {
        guard case .agentMessageChunk(let chunk) = update else { return false }
        output += chunk.content.text ?? ""
        return true
    }

    /// Whether `update`, arriving after the command finished, is a copy of its reply.
    public func isEcho(_ update: SessionUpdate) -> Bool {
        guard case .agentMessageChunk(let chunk) = update, let text = chunk.content.text else { return false }
        let echo = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !echo.isEmpty && output.contains(echo)
    }
}
