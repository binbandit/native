import Foundation
import NativeHostProtocol

extension HostCore {
    /// Stops agents and exits for good ("Quit Native and Stop Agents"), or exits for launchd to
    /// start the newer binary (an update): right away, or the first time nothing is running.
    func shutdown(stopAgents: Bool, immediately: Bool) async {
        if stopAgents {
            await stopAgentsAndExit()
        } else if immediately {
            // Turns stay committed; the new binary resumes them as interrupted by the update.
            isRestartingImmediately = true
            await finishCommandStops()
            exitForRestart()
        } else {
            isRestartingWhenIdle = true
            exitIfIdleForRestart()
        }
    }

    /// "Quit Native and Stop Agents": asks every running turn to stop, gives agents a moment to
    /// confirm, records what's left as stopped by the user, ends every agent's processes, and exits
    /// for good. Nothing is resumed at the next start.
    public func stopAgentsAndExit(confirmationWait: Duration = .milliseconds(1_500)) async {
        isStoppingAllAgents = true
        let running = sessions.values.filter { $0.turn != nil || $0.retryAt != nil }
        for session in running {
            await cancel(session)
        }
        let deadline = ContinuousClock.now + confirmationWait
        while running.contains(where: { $0.turn != nil }), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        // A stop can be mid-cleanup when Quit arrives. Its task must outlive the grace period and
        // verify exit before endTurn clears it or the host itself exits.
        await finishCommandStops()
        for link in agents.values {
            link.endNow()
        }
        for session in running {
            if session.turn != nil {
                endTurn(in: session, stopReason: "cancelled", pauseQueue: true)
                append(.turnEnded(stopReason: "cancelled"), to: session)
            }
            cancelRetry(of: session)
            journal(.stopped, session: session)
        }
        try? store.setMeta(MetaKey.cleanShutdown, "1")
        configuration.exit(ExitStatus.stopped)
    }

    private func finishCommandStops() async {
        // Another client can request Stop while cleanup suspends. Drain those requests too before
        // returning to the immediate exit path, which deliberately preserves other active turns.
        while !stoppingSessions.isEmpty {
            let stopping = Array(stoppingSessions.values)
            for session in stopping { session.stopRequestedAt = .distantPast }
            for session in stopping { await session.stopTimeout?.value }
        }
    }

    /// Exits for an update once nothing it would cut off is under way. Called whenever work ends,
    /// and on every heartbeat for work that ends quietly (a subagent working in the background).
    func exitIfIdleForRestart() {
        guard isRestartingWhenIdle, !isStoppingAllAgents, !isRestartingImmediately, stoppingSessions.isEmpty,
            !sessions.values.contains(where: \.holdsRestart)
        else { return }
        try? store.setMeta(MetaKey.cleanShutdown, "1")
        exitForRestart()
    }

    func exitForRestart() {
        guard stoppingSessions.isEmpty else {
            isRestartingWhenIdle = true
            return
        }
        if let build = pendingActivation, let updater = configuration.updates.selfUpdater {
            do {
                try updater.activate(build: build)
            } catch {
                // Stay on this build and say why; the install can be asked for again.
                pendingActivation = nil
                isRestartingWhenIdle = false
                isRestartingImmediately = false
                updateFailed(error)
                return
            }
        }
        // Read at the next start, so recovery says the host restarted to update, not that it crashed.
        try? store.setMeta(MetaKey.restartReason, "update")
        for link in agents.values {
            link.endNow()
        }
        configuration.exit(ExitStatus.restart)
    }
}
