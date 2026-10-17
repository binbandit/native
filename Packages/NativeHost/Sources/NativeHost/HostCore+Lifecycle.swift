import Foundation
import NativeHostProtocol

extension HostCore {
    /// Stops agents and exits for good ("Quit Native and Stop Agents"), or once nothing is running,
    /// exits for launchd to start the newer binary (an update).
    func shutdown(stopAgents: Bool) async {
        if stopAgents {
            for session in sessions.values where session.turn != nil {
                await cancel(session)
            }
            for link in agents.values {
                link.stop()
            }
            try? store.setMeta(MetaKey.cleanShutdown, "1")
            configuration.exit(ExitStatus.stopped)
        } else {
            isRestartingWhenIdle = true
            exitIfIdleForRestart()
        }
    }

    func exitIfIdleForRestart() {
        guard isRestartingWhenIdle, !sessions.values.contains(where: { $0.turn != nil || $0.phase == .recovering }) else { return }
        for link in agents.values {
            link.stop()
        }
        try? store.setMeta(MetaKey.cleanShutdown, "1")
        configuration.exit(ExitStatus.restart)
    }
}
