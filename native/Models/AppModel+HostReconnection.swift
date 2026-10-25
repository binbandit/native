import Foundation
import NativeHostClient
import NativeHostProtocol
import os

// A paired host's open tasks across a new pairing with it (docs/durability.md, "Host identity and
// many hosts"). Pairing the same host again, or undoing its removal, gives it a new client; the tasks
// still open on the old one move to it as they are (draft, transcript, queue, approvals) and catch up
// on what they missed, as they do after a dropped connection.
extension AppModel {
    /// Moves the tasks still open on `host`'s earlier clients to its client now, once that's
    /// connected to the host it paired with. Runs on every connection; only the first after a new
    /// pairing finds any.
    func reattachSessions(to host: RemoteHost) async {
        guard hosts.host(host.id) === host, let client = host.client, host.info?.hostID == host.id else { return }
        let retired = hosts.retiredClients(of: host)
        guard !retired.isEmpty else { return }
        var moved: [(session: SessionModel, link: HostSessionLink)] = []
        for old in retired {
            for session in sessions.sessions(on: old.client) {
                guard let link = session.host else { continue }
                // The new client attaches with the host's whole log; what the transcript has stays out.
                if let run = old.runs[link.id], let seq = session.mirror.lastSeq {
                    host.skipDelivered(link.id, through: HostEventMark(run: run, seq: seq))
                }
                link.move(to: client)
                if let summary = host.session(link.id) { session.apply(summary) }
                moved.append((session: session, link: link))
            }
        }
        hosts.forget(retired)
        for task in moved {
            await attach(task.session, task.link, through: client, on: host)
        }
    }

    /// Follows a moved task through its new client: what happened meanwhile replays, then live
    /// events follow.
    private func attach(
        _ session: SessionModel, _ link: HostSessionLink, through client: NativeHostClient, on host: RemoteHost
    ) async {
        do {
            let summary = try await client.attach(link.id)
            // A later pairing may have taken the task over meanwhile; its own attach answers for it.
            guard link.client === client else { return }
            session.apply(summary)
        } catch {
            // After a dropped connection the client attaches it again by itself.
            Self.logger.error(
                "Couldn't follow a task on \(host.name, privacy: .public) after pairing again: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
