import ACP
import Foundation

// Catching the user when an agent's process dies: Native restarts the agent, reopens the sessions
// that were in use, asks the ones it interrupted to carry on, and says so in each transcript. Kept
// apart so the durable host can take it over.
extension AppModel {
    /// Sent (not shown) to a session whose turn a crash cut off, so the agent knows to continue.
    static let interruptedTurnPrompt = "Your previous turn was interrupted because your process stopped unexpectedly. Continue where you left off."

    func handleCrash(of agent: AgentDefinition.ID) {
        let isRestarting = restartPolicies[agent, default: AgentRestartPolicy()].allowsRestart()
        let interrupted = sessions.disconnect(agent, isRestarting: isRestarting)
        guard isRestarting else { return }
        Task { await recover(agent, interrupted: interrupted) }
    }

    private func recover(_ agent: AgentDefinition.ID, interrupted: [SessionKey]) async {
        let previous = sessions.open(of: agent)
        guard let runtime = runtimes.replace(agent) else { return }
        await start(runtime, environment: await shellEnvironment())
        guard runtime.isReady else {
            // Keep the old transcripts on screen, with what went wrong and what to do.
            let reason = runtime.status.guidance ?? runtime.status.label
            for session in previous where session.origin == .user {
                session.addNotice("Native couldn't restart \(runtime.agent.displayName): \(reason)", isError: true)
            }
            return
        }
        sessions.removeAll(of: agent)
        // Reopen what the user had in front of them, and what was working.
        var reopen = interrupted
        if let selection, selection.agent == agent, !reopen.contains(selection) {
            reopen.append(selection)
        }
        for key in reopen {
            let old = previous.first { $0.key == key }
            if let old, !old.hasStarted {
                // The agent never saved it, so there's nothing to reopen; an empty one does as well.
                _ = await replaceEmptySession(old, on: runtime)
                continue
            }
            await loadSession(key)
            guard let session = sessions.session(key) else { continue }
            if interrupted.contains(key) {
                do {
                    try await session.submit(Self.interruptedTurnPrompt, .queue, echo: false)
                    session.addNotice("Native restarted \(runtime.agent.displayName) and asked it to continue where it left off. Press ⌘. to stop it.", isError: false)
                } catch {
                    session.addNotice("Native restarted \(runtime.agent.displayName), but couldn't ask it to continue: \(error.localizedDescription) Send a message to carry on.", isError: true)
                }
            } else {
                session.addNotice("Native restarted \(runtime.agent.displayName) after it stopped unexpectedly.", isError: false)
            }
        }
    }
}
