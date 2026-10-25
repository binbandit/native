import ACP
import Experiments
import Foundation
import NativeHostClient
import NativeHostProtocol

extension AppModel {
    /// The experiment is resolved here so menus and model actions use the same gate.
    var offersAgentChange: Bool { experiments.value(of: .changeAgent) }

    /// The agents where the task runs: a paired host's task continues only with that host's.
    func changeAgentChoices(for source: SessionModel) -> [AgentRuntime] {
        agentChangeRuntimes(at: agentChangePlace(of: source)).filter {
            $0.agent.id != source.agent.id && $0.isAvailable && !$0.needsSignIn
        }
    }

    func changeAgentBlock(for source: SessionModel) -> String? {
        if let reason = coordinatorConversationBlock(for: source.key) { return reason }
        guard offersAgentChange else { return "Enable Change Agent in Settings > Labs first." }
        guard sessions.session(source.key) === source, source.origin == .user,
            !source.isSubagent, !source.isEarlierConversation
        else {
            return "Open the current task to change its agent."
        }
        guard source.hasStarted else { return "Send a message in this task first." }
        if source.phase == .prompting || source.isRetryScheduled || source.isRunningHiddenCommand {
            return "Finish or stop the running turn before changing agents."
        }
        guard source.phase == .idle || source.phase == .disconnected, !source.isRestoringHistory else {
            return "Wait for the task to finish loading."
        }
        guard !source.hasQueuedPrompts else { return "Send or remove queued messages before changing agents." }
        guard !source.needsApproval else { return "Answer the task's pending requests before changing agents." }
        guard !source.children.values.contains(where: { $0.phase == .prompting }) else {
            return "Wait for the task's subagents to finish."
        }
        if let hold = source.turnHold { return hold }
        if let reason = remoteAgentChangeBlock(for: source) { return reason }
        guard catalog.lookup(source.key) != nil, !isArchived(source.key), !pendingDeletionKeys.contains(source.key),
            removedWorkspaces[source.key] == nil
        else {
            return "Open an active task with an available worktree."
        }
        return agentChangeGoalBlock(source)
    }

    func requestAgentChange(_ source: SessionModel) {
        guard offersAgentChange, changingAgent == nil else { return }
        changingAgent = ChangeAgentModel(source: source, app: self)
    }

    func prepareAgentChange(_ source: SessionModel, to agent: AgentDefinition.ID) async throws -> SessionModel {
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        let place = agentChangePlace(of: source)
        guard changeAgentChoices(for: source).contains(where: { $0.agent.id == agent }),
            let runtime = await startAgentChangeRuntime(agent, at: place)
        else { throw AgentChangeFailure(agentChangeStartFailure(of: agent, at: place)) }
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        let started = try await launcher.start(
            on: runtime, cwd: source.cwd, project: catalog.lookup(source.key)?.project)
        // Some agents list even empty conversations, and a host lists every one it has open. Keep the
        // unsent candidate out of the sidebar, including after quitting during review; an accepted
        // handoff removes this tombstone.
        deletedSessions.insert(started.key)
        let candidate = try currentAgentChangeTarget(started)
        if candidate !== started {
            unsentSessions.forget(started.key)
        }
        deletedSessions.insert(candidate.key)
        if place == .thisMac {
            unsentSessions.started(candidate.key)
            catalog.remove(candidate.key)
        } else {
            indexRemoteSessions()
        }
        return candidate
    }

    /// No worktree is created: the replacement runs at the exact folder the task already owns.
    /// The earlier conversation remains openable through Native's existing conversation chain.
    func finishAgentChange(
        _ source: SessionModel, to prepared: SessionModel, handoff: String, modelValue: String
    ) async throws {
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        let place = agentChangePlace(of: source)
        var target = try currentAgentChangeTarget(prepared)
        guard !source.isChangingAgent, target.agent.id != source.agent.id, target.cwd == source.cwd,
            agentChangePlace(of: target) == place, let project = catalog.lookup(source.key)?.project,
            !handoff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw AgentChangeFailure("The handoff is not ready. Cancel and try again.") }
        source.isChangingAgent = true
        defer { source.isChangingAgent = false }
        if let option = target.configOptions.first(where: { $0.category == "model" }),
            case .select(_, let choices) = option.kind, !modelValue.isEmpty
        {
            guard choices.contains(where: { $0.value == modelValue }) else {
                throw AgentChangeFailure("That model is no longer offered. Choose another model.")
            }
            await target.setConfigOption(option, to: modelValue)
            target = try currentAgentChangeTarget(target)
            guard case .select(let current, _) = target.configOptions.first(where: { $0.id == option.id })?.kind,
                current == modelValue
            else { throw AgentChangeFailure("Couldn't select that model. Choose another model or try again.") }
        }
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        target = try currentAgentChangeTarget(target)
        if let reason = target.sendBlockedReason { throw AgentChangeFailure(reason) }
        if !target.hasStarted {
            guard target.phase == .idle, !target.isRestoringHistory, !target.isRunningHiddenCommand,
                target.turnHold == nil
            else {
                throw AgentChangeFailure("The new agent is still getting ready. Wait a moment, then try again.")
            }
        }
        // Publishing marks a send attempt. A lost reply is not proof that nothing arrived,
        // so wait for transcript evidence instead of sending a second handoff on retry.
        guard deletedSessions.contains(target.key) || target.hasStarted else {
            throw AgentChangeFailure.unconfirmedHandoff
        }
        // Publish before sending so a quit or dropped reply can never hide work that reached
        // the new agent. Cancel removes an unused candidate; an accepted one stays recoverable.
        titles.rename(target.titleKey, to: source.displayTitle)
        target.draft = handoff
        if place == .thisMac {
            deletedSessions.remove(target.key)
            if !catalog.contains(target.key) {
                catalog.add(
                    SessionInfo(sessionId: target.id, cwd: source.cwd.folderPath, updatedAt: .now),
                    for: target.agent.id, in: project)
            }
        } else {
            publishRemoteAgentChange(target, in: project)
        }
        if !target.hasStarted {
            do {
                _ = try await target.submit(handoff, .queue)
            } catch {
                target = try currentAgentChangeTarget(target)
                guard target.hasStarted else { throw AgentChangeFailure.unconfirmedHandoff }
            }
            target = try currentAgentChangeTarget(target)
        }
        earlierConversations.record(target.key, after: source.key)
        earlierConversations.keep(target.key)
        ordering.replace(source.key, with: target.key)
        target.draft = source.draft
        target.attachments = source.attachments
        source.draft = ""
        source.attachments = []
        history.replace(source.key, with: target.key)
        selection = target.key
        target.wantsComposerFocus = true
    }

    /// An unsaved ACP conversation may get a new key when the host reloads it after idle unloading.
    /// Its stable host task owns the review; only that exact host, agent and folder may replace it.
    func followAgentChangeReplacement(_ old: SessionModel, with replacement: SessionModel) {
        guard sameAgentChangeHostTask(old, replacement),
            changingAgent?.replaceCandidate(old, with: replacement) == true
        else { return }
        let wasHidden = deletedSessions.contains(old.key)
        deletedSessions.insert(old.key)
        if wasHidden {
            deletedSessions.insert(replacement.key)
            catalog.remove(replacement.key)
        }
        if unsentSessions.contains(old.key) {
            unsentSessions.forget(old.key)
            unsentSessions.started(replacement.key)
        }
    }

    private func currentAgentChangeTarget(_ target: SessionModel) throws -> SessionModel {
        if sessions.session(target.key) === target { return target }
        if let host = target.host, let replacement = sessions.session(host: host.id),
            sameAgentChangeHostTask(target, replacement)
        {
            return replacement
        }
        throw AgentChangeFailure("The new agent is no longer available for this handoff. Cancel and try again.")
    }

    private func sameAgentChangeHostTask(_ old: SessionModel, _ replacement: SessionModel) -> Bool {
        guard let oldHost = old.host, let newHost = replacement.host else { return false }
        return oldHost.id == newHost.id && oldHost.client === newHost.client
            && old.agent.id == replacement.agent.id && old.cwd == replacement.cwd
    }

    func discardAgentChange(_ candidate: SessionModel) {
        // Only a candidate that never attempted a send can be hidden safely. Published
        // candidates stay openable even when the host has not confirmed their first turn.
        guard !candidate.hasStarted, deletedSessions.contains(candidate.key) else { return }
        deletedSessions.insert(candidate.key)
        unsentSessions.forget(candidate.key)
        catalog.remove(candidate.key)
        // Closed where it runs, by the agent that runs it: a paired host's candidate on that host.
        let runtime = agentChangeRuntimes(at: agentChangePlace(of: candidate)).first {
            $0.agent.id == candidate.agent.id
        }
        sessions.remove(candidate)
        let closes = runtime?.capabilities?.closeSessions == true
        if let link = candidate.host {
            Task { try? await link.client.closeSession(link.id, closeInAgent: closes) }
        } else if closes, let connection = candidate.connection {
            Task { _ = try? await connection.send(CloseSessionRequest(sessionId: candidate.id)) }
        }
    }
}

private struct AgentChangeFailure: LocalizedError {
    static let unconfirmedHandoff = AgentChangeFailure(
        "Couldn't confirm whether the new agent received the handoff. Cancel and check the new task before sending again."
    )
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
