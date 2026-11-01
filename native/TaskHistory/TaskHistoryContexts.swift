import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Observation
import os

/// The rest of a task, for its transcript (docs/decisions/2026-11-01-one-task-history.md, "The
/// transcript"). A conversation that a change of agent starts joins the task's history on its host,
/// and its transcript shows what the agents before it did, read from that history. Behind the
/// `task-history` gate; off, nothing joins and transcripts are as before.
@MainActor @Observable
final class TaskHistoryContexts {
    static let shared = TaskHistoryContexts()

    /// What a session's transcript shows before its own conversation.
    enum Context: Equatable {
        case loading
        case shown(TaskHistoryContext)
        /// Nothing recorded for it, or the host couldn't say: the transcript is as before.
        case unavailable
    }

    /// The newest items a transcript shows; older ones stay in the earlier conversations.
    static let shownLimit = 40

    /// Whether the `task-history` gate is on.
    @ObservationIgnored var isEnabled: () -> Bool = { false }
    /// An agent by its id, for the runs' headings; nil for an agent no longer available.
    @ObservationIgnored var agent: @MainActor (String) -> AgentDefinition? = { _ in nil }

    private var contexts: [HostSessionID: Context] = [:]

    private static let logger = Logger(subsystem: "dev.binbandit.native", category: "TaskHistory")

    func context(for session: SessionModel) -> Context? {
        session.host.flatMap { contexts[$0.id] }
    }

    /// Loads what the agents before `session` did, once: the items its handoff considered don't change.
    func load(_ session: SessionModel) async {
        guard isEnabled(), let host = session.host, contexts[host.id] == nil else { return }
        contexts[host.id] = .loading
        do {
            let summary = try await host.client.historySummary(of: host.id)
            guard let handoff = summary.handoff else {
                contexts[host.id] = .unavailable
                return
            }
            // Enough of the newest items to fill the limit once reasoning and endings are left out.
            let after = max(handoff.from, handoff.through - Self.shownLimit * 4)
            let items = try await host.client.readHistory(
                ReadHistoryParams(sessionID: host.id, after: after, through: handoff.through))
            let latest = TaskHistoryRun.latest(summary.runs(of: items, at: handoff), limit: Self.shownLimit)
            contexts[host.id] =
                latest.runs.isEmpty
                ? .unavailable
                : .shown(
                    TaskHistoryContext(
                        runs: latest.runs, omitsEarlier: latest.omitsEarlier || after > handoff.from, agent: agent))
        } catch {
            guard !Task.isCancelled else {
                // The transcript went away before it loaded; it loads again when it's back.
                contexts[host.id] = nil
                return
            }
            Self.logger.error("Couldn't read a task's history: \(error.localizedDescription, privacy: .public)")
            contexts[host.id] = .unavailable
        }
    }

    /// A change of agent started `session` to continue `earlier`, so it joins the task's history
    /// before its first message, when both run on the same host. Not for `/clear` and other restarts
    /// of the same agent: those leave the earlier conversation behind on purpose. A failure leaves
    /// the session a history of its own, as before.
    func join(_ session: SessionModel, continuing earlier: SessionModel?) async {
        guard isEnabled(), let earlier, earlier.agent.id != session.agent.id, let host = session.host,
            let source = earlier.host, host.client === source.client
        else { return }
        do {
            _ = try await host.client.joinHistory(
                JoinHistoryParams(
                    sessionID: host.id, sourceAgentID: earlier.agent.id.rawValue, sourceAgentSessionID: earlier.id))
        } catch {
            Self.logger.error("Couldn't join a task's history: \(error.localizedDescription, privacy: .public)")
        }
    }
}
