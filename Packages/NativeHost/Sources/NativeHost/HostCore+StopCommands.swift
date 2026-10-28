import Foundation

extension HostCore {
    /// ACP has no per-session process ownership. A stuck shared adapter must restart too; its
    /// other running sessions use crash recovery rather than holding this Stop open indefinitely.
    func endStoppedCommands(
        _ turn: UnfinishedTurn, in session: HostSession, on link: AgentLink, generation: Int,
        processes initial: AgentStopProcesses
    ) async {
        defer {
            stoppingSessions[session.id] = nil
            exitIfIdleForRestart()
        }
        var processes = initial
        while !Task.isCancelled {
            processes.refresh()
            let graceElapsed =
                session.stopRequestedAt.map { Date.now.timeIntervalSince($0) >= Self.stopGracePeriod } ?? true
            if graceElapsed {
                // No suspension between deciding to stop this generation and freezing its tree.
                if link.generation == generation { link.beginCommandStop() }
                processes.terminate()
                if !processes.hasRemainingProcesses {
                    if link.generation == generation {
                        link.commandsDidStop()
                        agentExited(session.record.agentID, generation: generation)
                    }
                    // Closing a task must not cancel its cleanup or resurrect its sidebar entry.
                    guard sessions[session.id] === session else { return }
                    finishForcedStop(turn, in: session)
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func finishForcedStop(_ turn: UnfinishedTurn, in session: HostSession) {
        guard session.turn?.requestID == turn.requestID else { return }
        let message =
            session.stopAcknowledged ? nil : "Stopped. \(session.agentName) didn't respond, so Native stopped it."
        // Reload the agent's conversation without replacing the host's richer transcript, including
        // partial tool calls and this stop receipt, with an incomplete agent-side replay.
        session.preservesTranscriptOnLoad = true
        endTurn(in: session, stopReason: "cancelled", pauseQueue: true)
        append(.turnEnded(stopReason: "cancelled", message: message), to: session)
        publish(session)
        continueAfterTurn(session)
        if !isStoppingAllAgents && !isRestartingImmediately {
            Task { try? await load(session) }
        }
    }
}
