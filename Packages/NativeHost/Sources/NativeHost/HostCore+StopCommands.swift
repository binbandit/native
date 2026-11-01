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
                        preserveStoppedDescendants(on: link)
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

    /// The retained parent cards must keep their backing sessions, including nested history.
    private func preserveStoppedDescendants(on link: AgentLink) {
        for session in sessions.values where session.record.agentID == link.spec.id && session.isStopping {
            session.preservesTranscriptOnLoad = true
            for child in subagents(of: session) {
                child.needsLoad = true
                child.reloadsQuietly = true
                withdrawQuestions(of: child)
                guard let ownerID = child.record.parentID, let owner = sessions[ownerID],
                    let agentID = child.record.agentSessionID
                else { continue }
                let working = owner.mirror.state.subagents.first { $0.id == agentID }?.workState?.isWorking == true
                let openTool = child.mirror.state.items.contains {
                    if case .toolCall(let call) = $0 { !call.status.isFinished } else { false }
                }
                if working || openTool {
                    child.record.lastStopReason = "cancelled"
                    append(.turnEnded(stopReason: "cancelled"), to: child)
                    append(
                        .update(
                            .object([
                                "sessionUpdate": .string("subagent_update"), "sessionId": .string(agentID.rawValue),
                                "state": .object(["state": .string("idle"), "stopReason": .string("cancelled")]),
                            ])), to: owner)
                }
            }
        }
    }

    func finishForcedStop(_ turn: UnfinishedTurn, in session: HostSession) {
        guard session.turn?.requestID == turn.requestID else { return }
        let message =
            session.stopAcknowledged ? nil : "Stopped. \(session.agentName) didn't respond, so Native stopped it."
        // Reload the agent's conversation without replacing the host's richer transcript, including
        // partial tool calls and this stop receipt, with an incomplete agent-side replay.
        session.preservesTranscriptOnLoad = true
        session.loadGeneration += 1
        session.loading = nil
        session.loadingConfigOptions = nil
        session.isReplayingPreservedTranscript = false
        for child in subagents(of: session) { child.isReplayingPreservedTranscript = false }
        if session.mirror.isLoading {
            showPendingMessage(of: session)
            append(.loaded, to: session)
        }
        endTurn(in: session, stopReason: "cancelled", pauseQueue: true)
        append(.turnEnded(stopReason: "cancelled", message: message), to: session)
        publish(session)
        continueAfterTurn(session)
        if !isStoppingAllAgents && !isRestartingImmediately {
            Task { try? await load(session) }
        }
    }
}
