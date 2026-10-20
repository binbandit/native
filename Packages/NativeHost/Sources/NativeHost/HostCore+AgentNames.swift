import ACP
import Foundation
import NativeHostProtocol
import SessionTitling

// Naming sessions in their agent (`AgentSpec.renameCommand`). codex-acp titles a new session itself
// after its first turn, with a model, on a thread of its own that it never lets go of: one more set
// of the user's MCP servers for every task, running as long as the adapter (codex-acp#628). A session
// named before its first turn ends is never titled that way, and codex-acp's `/rename` asks no model.
// Later names keep the agent's list of sessions (`codex resume`) in step with Native's titles.
extension HostCore {
    /// Names the session in its agent before `prompt` goes out, when the name the agent has isn't
    /// the one Native wants for it. Hidden from the transcript; a failure only means the agent keeps
    /// its own name.
    func nameInAgent(
        _ session: HostSession, beforeSending prompt: OutgoingPrompt, on link: AgentLink, peer: JSONRPCPeer
    ) async {
        guard let command = link.spec.renameCommand, !link.renameAsksModel,
            let agentSessionID = session.record.agentSessionID,
            let name = agentName(for: session, firstMessage: prompt.text), name != session.record.title
        else { return }
        // Anything it says stays out of the transcript.
        session.hiddenCommand = HiddenCommandCapture()
        defer { session.hiddenCommand = nil }
        do {
            let response = try await peer.request(
                "session/prompt", PromptRequest(sessionId: agentSessionID, prompt: [.text("\(command) \(name)")]),
                as: RawPromptUsageResponse.self)
            // A model answered instead of the agent itself: renaming would cost a turn every time.
            if response.usage.map({ $0 != .null }) == true || session.hiddenCommand?.output.isEmpty == false {
                link.renameAsksModel = true
                logger.error("\(link.spec.name) answered \(command) with a model's turn; no longer naming sessions")
            }
        } catch {
            logger.error("Couldn't name a \(session.agentName) session: \(error.localizedDescription)")
        }
    }

    /// The name the agent should have for the session: the user's title or Native's, as the host has
    /// them (`HostTitles`), and before either exists, a new session's first message's, so the agent
    /// doesn't title it itself.
    private func agentName(for session: HostSession, firstMessage: String) -> String? {
        if let title = session.titleState.user ?? session.titleState.generated {
            return title
        }
        guard session.record.title == nil, session.record.lastStopReason == nil, !session.record.isAdopted
        else { return nil }
        return SessionTitleRules.fallback(from: firstMessage)
    }
}
