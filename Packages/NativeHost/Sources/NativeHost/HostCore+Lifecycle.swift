import Foundation
import NativeHostProtocol

extension HostCore {
    /// Stops agents and exits for good ("Quit Native and Stop Agents"), or exits for launchd to
    /// start the newer binary (an update): right away, or the first time nothing is running.
    func shutdown(stopAgents: Bool, immediately: Bool) async {
        if stopAgents {
            for session in sessions.values where session.turn != nil {
                await cancel(session)
            }
            for link in agents.values {
                link.stop()
            }
            try? store.setMeta(MetaKey.cleanShutdown, "1")
            configuration.exit(ExitStatus.stopped)
        } else if immediately {
            // Turns stay committed; the new binary resumes them as interrupted by the update.
            exitForRestart()
        } else {
            isRestartingWhenIdle = true
            exitIfIdleForRestart()
        }
    }

    func exitIfIdleForRestart() {
        guard isRestartingWhenIdle, !sessions.values.contains(where: { $0.turn != nil || $0.phase == .recovering })
        else { return }
        try? store.setMeta(MetaKey.cleanShutdown, "1")
        exitForRestart()
    }

    func exitForRestart() {
        if let build = pendingActivation, let updater = configuration.updates.selfUpdater {
            do {
                try updater.activate(build: build)
            } catch {
                // Stay on this build and say why; the install can be asked for again.
                pendingActivation = nil
                isRestartingWhenIdle = false
                updateFailed(error)
                return
            }
        }
        // Read at the next start, so recovery says the host restarted to update, not that it crashed.
        try? store.setMeta(MetaKey.restartReason, "update")
        for link in agents.values {
            link.stop()
        }
        configuration.exit(ExitStatus.restart)
    }
}
