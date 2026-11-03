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

    /// By host session, and the marker for a context marker's (nil for the transcript's top).
    private var contexts: [Key: Context] = [:]

    private struct Key: Hashable {
        let session: HostSessionID
        let marker: String?
    }

    private static let logger = Logger(subsystem: "dev.binbandit.native", category: "TaskHistory")

    /// What `session`'s transcript shows at its top (no marker) or with one of its context markers.
    func context(for session: SessionModel, marker: String? = nil) -> Context? {
        session.host.flatMap { contexts[Key(session: $0.id, marker: marker)] }
    }

    /// Loads what the agents before `session` did, for its top or for one of its context markers,
    /// once it's known: what a transfer considered doesn't change. A failure isn't remembered, so
    /// the transcript tries again when it's next opened.
    func load(_ session: SessionModel, marker: String? = nil) async {
        guard isEnabled(), let host = session.host else { return }
        let key = Key(session: host.id, marker: marker)
        guard contexts[key] == nil else { return }
        contexts[key] = .loading
        do {
            // Waits out a host that's restarting or reconnecting, once.
            let found = try await host.request { client in
                if let marker {
                    try await client.markerRuns(
                        of: host.id, markerID: marker, earlierMarkers: Self.markers(before: marker, in: session),
                        limit: Self.shownLimit)
                } else {
                    try await client.handoffRuns(of: host.id, limit: Self.shownLimit)
                }
            }
            contexts[key] =
                if let found, !found.runs.isEmpty {
                    .shown(TaskHistoryContext(runs: found.runs, omitsEarlier: found.omitsEarlier, agent: agent))
                } else {
                    .unavailable
                }
        } catch {
            if !Task.isCancelled {
                Self.logger.error("Couldn't read a task's history: \(error.localizedDescription, privacy: .public)")
            }
            contexts[key] = nil
        }
    }

    /// The host transfers' markers the transcript has above `marker`: what they showed isn't shown
    /// again at it.
    private static func markers(before marker: String, in session: SessionModel) -> Set<String> {
        let ids = session.state.items.compactMap { item -> String? in
            guard case .message(let message) = item, let id = message.preamble?.id,
                TaskHistoryTransfer.isMarkerID(id)
            else { return nil }
            return id
        }
        return Set(ids.prefix { $0 != marker })
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
