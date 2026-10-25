import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import TaskList

// Routing Native's host's events to the models of the sessions running there (`HostSessions`).
// The host client hands events over one at a time, in order, before the answers to requests made
// after them, so nothing here may wait on the host itself.
extension SessionStore {
    /// A replay a session sends before its model exists is short; this only guards against a
    /// session no model ever claims.
    private static let bufferLimit = 20_000

    /// The model of a host session, by the host's id for it.
    func session(host id: HostSessionID) -> SessionModel? {
        hostSessions[id].flatMap { session($0) }
    }

    /// The models following host sessions through `client`, subagents included, each once.
    func sessions(on client: NativeHostClient) -> [SessionModel] {
        hostSessions.compactMap { id, key in
            session(key).flatMap { $0.host?.id == id && $0.host?.client === client ? $0 : nil }
        }
    }

    /// Routes one of the host's events.
    func handle(_ event: NativeHostClient.Event) {
        switch event {
        case .sessionEvent(let id, let step):
            if let session = session(host: id) {
                deliver(step, to: session)
            } else if hostBuffered[id, default: []].count < Self.bufferLimit {
                hostBuffered[id, default: []].append(step)
            }
        case .sessionChanged(let summary):
            recordActivity(summary)
            hostSummaries[summary.id] = summary
            guard let session = session(host: summary.id) else { return }
            if let agentSessionID = summary.agentSessionID, agentSessionID != session.id, session.origin != .announced {
                onAgentSessionReplaced?(session, summary)
            } else {
                session.apply(summary)
            }
        case .sessionClosed(let id):
            hostSummaries[id] = nil
            hostBuffered[id] = nil
            // The host stopped tracking it (deleted, or closed by another client); its history
            // stays with the agent, and opening it again reopens it there.
            if let session = session(host: id) {
                hostSessions[id] = nil
                remove(session)
            }
        default:
            break
        }
    }

    /// The host knows about completed turns before their transcripts are opened in this client.
    func recordActivity(_ summary: HostSessionSummary) {
        guard let id = summary.agentSessionID else { return }
        activityDates.record(summary.lastActivity, for: SessionKey(agent: .init(rawValue: summary.agentID), id: id))
    }

    /// What arrived for a session before its model was registered: what happened before this
    /// model followed it, so it rebuilds the transcript without reaching plugins again.
    func deliverBuffered(to session: SessionModel, in host: HostSessionLink) {
        guard let steps = hostBuffered.removeValue(forKey: host.id) else { return }
        session.isReplaying = true
        for step in steps {
            deliver(step, to: session)
        }
        session.isReplaying = false
        session.announceReplay()
    }

    /// Stops following a session the app no longer shows. The host keeps running it.
    func stopFollowing(_ host: HostSessionLink) {
        hostSessions[host.id] = nil
        hostBuffered[host.id] = nil
        Task { try? await host.client.detach(host.id) }
    }

    private func deliver(_ step: SessionMirror.Step, to session: SessionModel) {
        // An agent announces a subagent on its parent first; the host has made the subagent a
        // session of its own just before, so it's followed from here on.
        if case .subagent(let subagent)? = step.update, session.child(subagent.sessionId) == nil {
            let child: SessionModel
            if case .update(let update) = step.event.payload,
                let claimed = claimSubagent?(session, subagent.sessionId, update)
            {
                child = claimed
            } else {
                let summary = hostSummaries.values.first {
                    $0.parentID == session.host?.id && $0.agentSessionID == subagent.sessionId
                }
                child = session.addSubagent(subagent.sessionId, host: summary)
            }
            register(child)
            if let link = child.host {
                follow(child, link)
            }
        }
        session.receive(step)
    }

    /// Follows a subagent's host session: its events so far replay first, then live ones follow.
    private func follow(_ child: SessionModel, _ link: HostSessionLink) {
        child.isReplaying = true
        Task {
            if let summary = try? await link.client.attach(link.id) {
                child.apply(summary)
            }
            child.isReplaying = false
            child.announceReplay()
        }
    }
}
