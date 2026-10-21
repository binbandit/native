import Foundation

extension HostCore {
    /// A session/cancel response says the turn ended, not that its commands exited. ACP does not
    /// attribute subprocesses to sessions, so ending the shared tree must wait for other tasks.
    func endStoppedCommands(
        _ turn: UnfinishedTurn, in session: HostSession, on link: AgentLink, generation: Int,
        processes initial: AgentStopProcesses
    ) async {
        var processes = initial
        var explainedSharedProcess = false
        var explainedSlowExit = false
        var terminatingSince: Date?
        while !Task.isCancelled {
            processes.refresh()
            let graceElapsed =
                session.stopRequestedAt.map { Date.now.timeIntervalSince($0) >= Self.stopGracePeriod } ?? true
            let sharesProcess =
                terminatingSince == nil && !isStoppingAllAgents && link.generation == generation
                && (link.isSigningIn
                    || sessions.values.contains {
                        $0.record.agentID == session.record.agentID && $0 !== session && !$0.isStopping
                            && ($0.isWorking || $0.loading != nil)
                    })
            if graceElapsed && sharesProcess {
                if !explainedSharedProcess {
                    append(
                        .notice(
                            text:
                                "Commands may still be running. \(session.agentName) shares its process with another task. Native will finish stopping when its other tasks finish or you stop them too.",
                            isError: true), to: session)
                    explainedSharedProcess = true
                }
            } else if graceElapsed {
                terminatingSince = terminatingSince ?? .now
                // No suspension between deciding the tree is exclusive and freezing it.
                if link.generation == generation { link.beginCommandStop() }
                processes.terminate()
                if !processes.hasRemainingProcesses {
                    if link.generation == generation {
                        link.commandsDidStop()
                        agentExited(session.record.agentID, generation: generation)
                    }
                    // Closing a task must not cancel its cleanup or resurrect its sidebar entry.
                    guard sessions[session.id] === session else { return }
                    session.stopRequestedAt = nil
                    append(
                        .notice(text: "Native ended \(session.agentName) and its running commands.", isError: false),
                        to: session)
                    finish(turn, in: session, stopReason: "cancelled")
                    return
                }
                if let terminatingSince, Date.now.timeIntervalSince(terminatingSince) >= 2, !explainedSlowExit {
                    append(
                        .notice(
                            text:
                                "Commands may still be running. Native could not confirm that every command exited and is still trying to stop them.",
                            isError: true), to: session)
                    explainedSlowExit = true
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
