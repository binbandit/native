#if DEBUG
import ACP
import Foundation

/// Subagents in every work state, folded through `SessionState` as the app receives them from
/// Claude Code's adapter (`subagent_update`).
enum SubagentPreviewFixtures {
    static let subagents: [SubagentState] = {
        var state = SessionState()
        let updates = [
            SubagentUpdate(
                sessionId: SessionID("a7c82d0a6f0097318"), title: .set("Explore"),
                description: .set("Find where the composer queues follow-ups and how Send Now reorders them"),
                canCancel: .set(true), state: .set(.running)),
            SubagentUpdate(
                sessionId: SessionID("a7c82d0a6f0097319"), title: .set("general-purpose"),
                description: .set("Run the ACP package tests and report failures"), state: .set(.requiresAction)),
            SubagentUpdate(
                sessionId: SessionID("a7c82d0a6f009731a"), title: .set("code-reviewer"),
                description: .set("Review the queue changes for races"),
                state: .set(.idle(stopReason: .endTurn, error: nil))),
            SubagentUpdate(
                sessionId: SessionID("a7c82d0a6f009731b"), title: .set("general-purpose"),
                description: .set("Profile the transcript while it streams"),
                state: .set(
                    .idle(stopReason: .error, error: RPCError(code: -32603, message: "Internal error: tool timed out")))
            ),
            SubagentUpdate(
                sessionId: SessionID("a7c82d0a6f009731c"), title: .set("Explore"),
                description: .set("List the views that read AppModel"),
                state: .set(.idle(stopReason: .cancelled, error: nil))),
        ]
        for update in updates {
            state.apply(.subagent(update))
        }
        return state.subagents
    }()
}
#endif
