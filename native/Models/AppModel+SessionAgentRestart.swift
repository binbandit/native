import Foundation
import NativeHostClient

extension AppModel {
    /// A task's Restart always addresses its owning host, even when another host runs the same agent.
    func restartAgent(for session: SessionModel) async {
        guard let link = session.host, link.client !== runtimes.host else {
            await restart(session.agent.id)
            return
        }
        guard let host = hosts.all.first(where: { $0.client === link.client }), host.isOnline else {
            session.addNotice("Reconnect the task's host in Settings > Hosts to restart its agent.", isError: true)
            return
        }
        do {
            let agent = try await link.client.restartAgent(session.agent.id.rawValue)
            host.runtime(session.agent.id)?.apply(agent)
        } catch {
            session.addNotice(
                "Couldn't restart the agent on \(host.name): \(error.localizedDescription)", isError: true)
        }
    }
}
