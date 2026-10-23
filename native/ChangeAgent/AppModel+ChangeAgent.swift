import ACP
import Experiments
import Foundation

extension AppModel {
    /// The experiment is resolved here so menus and model actions use the same gate.
    var offersAgentChange: Bool { experiments.value(of: .changeAgent) }

    func changeAgentChoices(for source: SessionModel) -> [AgentRuntime] {
        agents.filter { $0.agent.id != source.agent.id && $0.isAvailable && !$0.needsSignIn }
    }

    func changeAgentBlock(for source: SessionModel) -> String? {
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
        if let host = source.host, launcher.isRemote(host.client) {
            return "Changing agents on paired hosts is not available yet."
        }
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
        guard changeAgentChoices(for: source).contains(where: { $0.agent.id == agent }),
            let runtime = await ensureRunning(agent)
        else { throw AgentChangeFailure(startFailure(of: agent)) }
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        let candidate = try await launcher.start(
            on: runtime, cwd: source.cwd, project: catalog.lookup(source.key)?.project)
        // Some agents list even empty conversations. Keep the unsent candidate out of the sidebar,
        // including after quitting during review; an accepted handoff removes this tombstone.
        deletedSessions.insert(candidate.key)
        unsentSessions.started(candidate.key)
        catalog.remove(candidate.key)
        return candidate
    }

    /// No worktree is created: the replacement runs at the exact folder the task already owns.
    /// The earlier conversation remains openable through Native's existing conversation chain.
    func finishAgentChange(
        _ source: SessionModel, to target: SessionModel, handoff: String, modelValue: String
    ) async throws {
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        guard !source.isChangingAgent, target.agent.id != source.agent.id, target.cwd == source.cwd,
            let project = catalog.lookup(source.key)?.project,
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
            guard case .select(let current, _) = target.configOptions.first(where: { $0.id == option.id })?.kind,
                current == modelValue
            else { throw AgentChangeFailure("Couldn't select that model. Choose another model or try again.") }
        }
        if let reason = changeAgentBlock(for: source) { throw AgentChangeFailure(reason) }
        if let reason = target.sendBlockedReason { throw AgentChangeFailure(reason) }
        if !target.hasStarted {
            guard target.phase == .idle, !target.isRestoringHistory, !target.isRunningHiddenCommand,
                target.turnHold == nil
            else {
                throw AgentChangeFailure("The new agent is still getting ready. Wait a moment, then try again.")
            }
        }
        // Publish before sending so a quit or dropped reply can never hide work that reached
        // the new agent. Cancel removes an unused candidate; an accepted one stays recoverable.
        titles.rename(target.titleKey, to: source.displayTitle)
        target.draft = handoff
        deletedSessions.remove(target.key)
        if !catalog.contains(target.key) {
            catalog.add(
                SessionInfo(sessionId: target.id, cwd: source.cwd.folderPath, updatedAt: .now),
                for: target.agent.id, in: project)
        }
        if !target.hasStarted {
            do {
                _ = try await target.submit(handoff, .queue)
            } catch {
                guard target.hasStarted else { throw error }
            }
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

    func discardAgentChange(_ candidate: SessionModel) {
        guard !candidate.hasStarted else { return }
        deletedSessions.insert(candidate.key)
        unsentSessions.forget(candidate.key)
        catalog.remove(candidate.key)
        if let runtime = runtime(candidate.agent.id), candidate.host != nil {
            closeOnHost(candidate, on: runtime)
        } else {
            sessions.remove(candidate)
            if runtime(candidate.agent.id)?.capabilities?.closeSessions == true, let connection = candidate.connection {
                Task { _ = try? await connection.send(CloseSessionRequest(sessionId: candidate.id)) }
            }
        }
    }
}

private struct AgentChangeFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
