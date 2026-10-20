import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

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
            let summary = hostSummaries.values.first {
                $0.parentID == session.host?.id && $0.agentSessionID == subagent.sessionId
            }
            let child = session.addSubagent(subagent.sessionId, host: summary)
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
