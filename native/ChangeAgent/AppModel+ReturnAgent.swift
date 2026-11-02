import ACP
import Experiments
import Foundation
import NativeHostClient
import NativeHostProtocol

// Switching back to an agent the task already used (docs/decisions/2026-11-01-one-task-history.md,
// "Switching back with a delta"): the change reopens that agent's own conversation, and the host
// sends it only what it missed with its next message. Behind the `task-history` gate; off, every
// change of agent starts a new conversation, as before.
extension AppModel {
    /// The conversation this task already had on `choice`'s agent, to return to instead of starting
    /// another: in the task's chain of earlier conversations, on the same host as `source`, and on an
    /// agent that can load it. Nil starts a new conversation.
    func returningConversation(for choice: ComposerAgentModel, from source: SessionModel) async -> SessionModel? {
        guard experiments.value(of: .taskHistory), let host = source.host,
            agentChangeRuntimes(at: agentChangePlace(of: source)).first(where: { $0.agent.id == choice.agent })?
                .capabilities?.loadSession == true
        else { return nil }
        var key = source.key
        var seen: Set<SessionKey> = [key]
        while let earlier = earlierConversations.conversation(before: key), seen.insert(earlier).inserted {
            if earlier.agent == choice.agent {
                // A conversation that never took a message still waits for its own handoff; one in
                // another history (from before the gate, or set aside by `/clear`) can't be told
                // what it missed. Either starts a new conversation instead.
                guard !sessions.services.modelContinuations.hasPending(earlier) else { return nil }
                if sessions.session(earlier) == nil { await loadSession(earlier) }
                guard let session = sessions.session(earlier), session.hasStarted,
                    session.host?.client === host.client, await Self.finishesLoading(session),
                    await Self.shareHistory(session, source)
                else { return nil }
                return session
            }
            key = earlier
        }
        return nil
    }

    /// Whether two conversations are in one task history on their host, so a return can be told
    /// exactly what it missed.
    private static func shareHistory(_ session: SessionModel, _ source: SessionModel) async -> Bool {
        guard let link = session.host, let sourceLink = source.host,
            let returning = try? await link.client.historySummary(of: link.id),
            let current = try? await sourceLink.client.historySummary(of: sourceLink.id)
        else { return false }
        return returning.id == current.id
    }

    /// Whether a reopened conversation finished replaying its history in time to be returned to.
    private static func finishesLoading(_ session: SessionModel) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while session.phase != .idle || session.isRestoringHistory {
            guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    /// A return was undone: the context its host prepared for the conversation's next message won't
    /// go, and the conversation stays open, as it was before.
    func withdrawReturn(to target: SessionModel) {
        guard let link = target.host else { return }
        Task { _ = try? await link.client.withdrawHistory(of: link.id) }
    }
}
