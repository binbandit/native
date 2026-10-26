import ACP
import Foundation
import NativeHostProtocol

// The organization's policy on this host (docs/enterprise/host-policy.md): read from the machine
// before anything else starts, refreshed while the host runs, and checked again where each side
// effect happens, so work that slips past a client's request (recovery, queues, tasks agents hand
// each other) is held to it too. Revoking a capability ends what uses it and leaves the record.
extension HostCore {
    func allows(_ capability: HostCapability) -> Bool {
        policy.allows(capability)
    }

    /// Refuses unless the policy allows `capability`.
    func require(_ capability: HostCapability) throws {
        guard allows(capability) else { throw HostPolicyDenial(capability.action, policy: policy) }
    }

    /// Refuses unless the policy allows agents, and this one (`policy.agents.allowed`).
    func require(agent id: String) throws {
        try require(.agents)
        guard policy.allows(agent: id) else {
            let action = agents[id]?.spec.routeIdentity == nil ? "start \(agents[id]?.spec.name ?? id)" : "start agents"
            throw HostPolicyDenial(action, policy: policy)
        }
        if let spec = agents[id]?.spec {
            do {
                try HostAgentRouteAdmission.check(spec, policy: policy)
            } catch {
                // Route/configuration values and raw adapter failures never enter denial messages.
                throw HostPolicyDenial("start agents", policy: policy)
            }
        }
    }

    private func allowsAgentRoute(_ id: String) -> Bool {
        (try? require(agent: id)) != nil
    }

    /// Refuses a request the policy doesn't allow, before its params are read. Outside ordinary
    /// mode a method this host doesn't know is refused too, whatever it is.
    func admit(_ method: String) throws {
        switch HostMethodAdmission(method) {
        case .always:
            return
        case .needs(let capability):
            try require(capability)
        case .unknown:
            guard policy.mode == .ordinary else { throw HostPolicyDenial("do that", policy: policy) }
        }
    }

    /// Calls `handler` with every policy that replaces the current one: the paired-device gateway
    /// follows the host's policy this way.
    public func observePolicy(_ handler: @escaping @HostActor (HostPolicy) -> Void) {
        policyObservers.append(handler)
    }

    /// Reads the policy again now and then, so a profile installed or removed while no app runs
    /// still takes effect.
    func refreshPolicyPeriodically() {
        let interval = configuration.policyRefreshInterval
        policyRefresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                self?.refreshPolicy()
            }
        }
    }

    func refreshPolicy() {
        apply(configuration.policy.current())
    }

    /// Takes `newPolicy`: ends whatever it no longer allows, starts what it newly allows and tells
    /// observers.
    func apply(_ newPolicy: HostPolicy) {
        guard newPolicy != policy else { return }
        let previous = policy
        policy = newPolicy
        logger.info(
            "Policy is \(newPolicy.mode.rawValue) now, allowing \(newPolicy.capabilities.map(\.rawValue).sorted())")
        let revoked = previous.capabilities.subtracting(newPolicy.capabilities)
        let granted = newPolicy.capabilities.subtracting(previous.capabilities)
        endDeniedAgentWork()
        if revoked.contains(.loginShell) { forgetEnvironment() }
        if !allowsDoctorChecks {
            for run in doctorRuns.values { run.cancel() }
        }
        if revoked.contains(.commands) {
            for command in clients.values.flatMap(\.commands.values) { command.cancel() }
        }
        if revoked.contains(.files) {
            for client in clients.values { stopFileWatches(of: client) }
        }
        if revoked.contains(.updates) { stopUpdates() }
        if granted.contains(.updates) { startUpdates() }
        if revoked.contains(.agentTools) { tasks.stop() }
        if granted.contains(.agentTools) { tasks.start() }
        if revoked.contains(.updates) || granted.contains(.updates) { publishUpdate() }
        for observer in policyObservers { observer(newPolicy) }
    }

    /// The policy no longer allows some agents, or any: their turns end (paused, so nothing is sent
    /// again without the user, here or after a restart), their recoveries and retries stop, and
    /// their process trees are ended. Transcripts, queues and sessions stay.
    private func endDeniedAgentWork() {
        endDeniedAgentTurns()
        // A Stop already owns its turn's processes: it ends them now, without waiting out its grace
        // period, and sends nothing after.
        for session in stoppingSessions.values where !allowsAgentRoute(session.record.agentID) {
            session.stopRequestedAt = .distantPast
            session.sendAfterStop = nil
        }
        // A starting agent ends too: its launch checks the policy again before it spawns anything.
        for link in agents.values
        where !allowsAgentRoute(link.spec.id) && (link.status == .ready || link.status == .starting) {
            let generation = link.generation
            link.end()
            agentExited(link.spec.id, generation: generation)
        }
        exitIfIdleForRestart()
    }

    /// Ends every turn of an agent the policy doesn't allow, with the reason, and pauses its queue.
    /// Run when agents are revoked, and again whenever a launch is refused: a turn committed since
    /// (a task handing another a message, a queue draining) can't run, so it ends now instead of
    /// waiting for a restart.
    func endDeniedAgentTurns() {
        for session in sessions.values where !allowsAgentRoute(session.record.agentID) {
            let denial = denial(forAgentOf: session)
            session.isRecoveryCancelled = true
            let wasRetrying = session.retryAt != nil
            cancelRetry(of: session)
            var changed = wasRetrying
            if session.turn != nil, stoppingSessions[session.id] == nil {
                endTurn(in: session, stopReason: "error", pauseQueue: true)
                append(
                    .turnFailed(message: denial.localizedDescription, error: denial.rpcError, retry: nil), to: session)
                journal(.turnFailed, session: session, detail: denial.localizedDescription)
                changed = true
            }
            if pauseQueue(of: session) { changed = true }
            if changed { publish(session) }
        }
    }

    /// At startup, for agents the policy doesn't allow: what the previous run left unfinished ends
    /// with the reason instead of resuming, and waiting messages stay waiting.
    func concludeBlockedTurns(_ turns: [UnfinishedTurn], cause: RecoveryNote.Cause, lastSeenAlive: Date?) throws {
        for turn in turns {
            guard let session = sessions[turn.sessionID] else {
                try store.finishTurn(turn.sessionID)
                continue
            }
            let denial = denial(forAgentOf: session)
            session.turn = turn
            endTurn(in: session, stopReason: "error", pauseQueue: true)
            let note = RecoveryNote(
                cause: cause, action: .failed, agentName: session.agentName,
                interruptedAt: max(lastSeenAlive ?? turn.startedAt, turn.startedAt),
                problem: denial.localizedDescription)
            append(.recovered(note), to: session)
            journal(.recovered, session: session, recovery: note)
        }
        for session in sessions.values where !allowsAgentRoute(session.record.agentID) {
            pauseQueue(of: session)
        }
    }

    private func denial(forAgentOf session: HostSession) -> HostPolicyDenial {
        let action =
            agents[session.record.agentID]?.spec.routeIdentity == nil ? "start \(session.agentName)" : "start agents"
        return allows(.agents)
            ? HostPolicyDenial(action, policy: policy)
            : HostPolicyDenial(HostCapability.agents.action, policy: policy)
    }

    /// Even an empty queue: a message put back into it later waits for the user too. True if it wasn't.
    @discardableResult
    private func pauseQueue(of session: HostSession) -> Bool {
        guard !session.record.isQueuePaused else { return false }
        session.record.isQueuePaused = true
        try? store.updateSession(session.record)
        return true
    }
}
