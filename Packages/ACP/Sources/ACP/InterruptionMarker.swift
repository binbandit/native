/// What an agent writes into its own history when the user stops a turn. Claude Code records the
/// stop as a user message, "[Request interrupted by user]", or "[Request interrupted by user for
/// tool use]" when a tool was running, and replays it with the session's history as if the user had
/// typed it (captured from claude-agent-acp 0.93.0 and Claude Code 2.1.304). Codex records its
/// interruptions as developer messages, which codex-acp 2.2.2 doesn't replay.
///
/// Only a message that is exactly one of these is the agent's, so a prompt that quotes one stays
/// the user's.
public enum InterruptionMarker: String, CaseIterable, Sendable {
    case whileResponding = "[Request interrupted by user]"
    /// The stop cut off the tools that were running.
    case whileUsingTools = "[Request interrupted by user for tool use]"

    public static let texts = Set(allCases.map(\.rawValue))

    init?(_ chunk: ContentChunk) {
        guard case .text(let text) = chunk.content else { return nil }
        self.init(rawValue: text)
    }
}
