import ACP
import Experiments
import Foundation
import NativePolicy

extension AppModel {
    func restoreAgentModelChoice(for session: SessionModel) {
        guard offersAgentModels, session.modelChange == nil,
            let record = sessions.services.modelContinuations.receipt(for: session.key)
        else { return }
        session.modelChange = ComposerAgentChange(restoring: record, current: session, app: self)
        session.continuedTaskKey = record.source
    }

    var offersAgentModels: Bool { offersAgentChange && experiments.value(of: .composerNext) }

    /// Only explicit loads create a conversation. Opening or hovering reads Native-owned caches
    /// and already loaded sessions on this exact host.
    func agentModels(for source: SessionModel) -> [ComposerAgentModel] {
        guard offersAgentModels else { return [] }
        let place = agentChangePlace(of: source)
        let runtimes = agentChangeRuntimes(at: place)
        var result = modelEntries(
            agent: source.agent.id, name: source.agentName, options: source.configOptions,
            reason: remoteAgentChangeBlock(for: source), isManaged: false)
        result += runtimes.filter { $0.agent.id != source.agent.id }.flatMap { runtime -> [ComposerAgentModel] in
            modelEntries(
                agent: runtime.agent.id, name: runtime.agent.displayName,
                options: agentModelOptions(runtime, place: place),
                reason: agentModelBlock(source, runtime: runtime), isManaged: false)
        }
        // Admission removes forbidden agents from runtimes. Keep known model identities readable,
        // without making a denied agent executable or starting it to discover more.
        if place == .thisMac {
            for agent in plugins.agents where !runtimes.contains(where: { $0.agent.id == agent.id }) {
                let cached = AgentSessionDefaults.offeredOptions(for: agent.id)
                result += modelEntries(
                    agent: agent.id, name: agent.displayName, options: cached.isEmpty ? nil : cached,
                    reason: "Not available on this Mac. Open Agents Settings to check this agent.", isManaged: false)
            }
            let policy = plugins.policyCenter.policy
            for plugin in plugins.plugins {
                for agent in plugin.plugin.manifest.agents where !policy.agents.allows(agent.id) {
                    let id = AgentDefinition.ID(rawValue: agent.id)
                    let options = AgentSessionDefaults.offeredOptions(for: id)
                    result += modelEntries(
                        agent: id, name: agent.name, options: options, reason: "Not allowed", isManaged: true)
                }
            }
        }
        return result
    }

    private func agentModelOptions(_ runtime: AgentRuntime, place: AgentChangePlace) -> [ConfigOption]? {
        if let options = agentModelCatalogs[ObjectIdentifier(runtime)] { return options }
        if let session = sessions.loadedSessions.first(where: {
            $0.agent.id == runtime.agent.id && agentChangePlace(of: $0) == place && $0.phase == .idle
        }) {
            return session.configOptions
        }
        let cached = place == .thisMac ? AgentSessionDefaults.offeredOptions(for: runtime.agent.id) : []
        return cached.isEmpty ? nil : cached
    }

    private func modelEntries(
        agent: AgentDefinition.ID, name: String, options: [ConfigOption]?, reason: String?, isManaged: Bool
    ) -> [ComposerAgentModel] {
        if let options {
            let model = options.first { $0.category == "model" }.flatMap(SelectSetting.init)
            if let model, !model.choices.isEmpty {
                return model.choices.map {
                    .init(
                        agent: agent, agentName: name, choice: $0, kind: .model($0.value),
                        unavailable: reason, isManaged: isManaged)
                }
            }
            return [
                .init(
                    agent: agent, agentName: name, choice: .init(value: "", name: "\(name) Default"),
                    kind: .model(nil), unavailable: reason, isManaged: isManaged)
            ]
        }
        return [
            .init(
                agent: agent, agentName: name,
                choice: .init(value: "", name: "Load \(name) Models…"), kind: .load,
                unavailable: reason, isManaged: isManaged)
        ]
    }

    func agentModelBlock(_ source: SessionModel, runtime: AgentRuntime) -> String? {
        guard plugins.policyCenter.policy.agents.allows(runtime.agent.id.rawValue) else { return "Not allowed" }
        if let reason = remoteAgentChangeBlock(for: source) { return reason }
        if runtime.needsSignIn { return "Sign in required. Open Agents Settings to sign in." }
        if !runtime.isAvailable { return runtime.status.guidance ?? runtime.status.label }
        if source.needsApproval || source.pendingQuestion != nil { return "Answer \(source.agentName) first." }
        if source.hasQueuedPrompts { return "Send or remove queued messages first." }
        if let reason = modelChangeGoalBlock(source) { return reason }
        if source.phase == .prompting, !source.isRetryScheduled, !source.isStopping,
            !source.isRunningHiddenCommand, !source.isSubagent,
            !source.children.values.contains(where: { $0.phase == .prompting }),
            coordinatorConversationBlock(for: source.key) == nil
        {
            return nil
        }
        return changeAgentBlock(for: source)
    }

    func loadAgentModels(_ row: ComposerAgentModel, for source: SessionModel) async throws {
        let target = try await prepareModelRuntime(row, for: source)
        defer { discardAgentChange(target) }
        guard
            let runtime = agentChangeRuntimes(at: agentChangePlace(of: source)).first(where: {
                $0.agent.id == row.agent
            })
        else { throw ComposerAgentChange.Failure("That agent is no longer available.") }
        agentModelCatalogs[ObjectIdentifier(runtime)] = target.configOptions
    }

    /// Starting a candidate bypasses task-start hooks and defaults that belong to a working task.
    /// No prompt, title request, file operation or worktree allocation occurs here.
    func prepareModelRuntime(_ row: ComposerAgentModel, for source: SessionModel) async throws -> SessionModel {
        let place = agentChangePlace(of: source)
        guard let offered = agentChangeRuntimes(at: place).first(where: { $0.agent.id == row.agent }) else {
            throw ComposerAgentChange.Failure("That agent is no longer available on this host.")
        }
        if let reason = agentModelBlock(source, runtime: offered) { throw ComposerAgentChange.Failure(reason) }
        guard let runtime = await startAgentChangeRuntime(row.agent, at: place) else {
            throw ComposerAgentChange.Failure("Couldn't start \(row.agentName). \(source.agentName) is still selected.")
        }
        if let reason = agentModelBlock(source, runtime: runtime) { throw ComposerAgentChange.Failure(reason) }
        let target = try await launcher.start(
            on: runtime, cwd: source.cwd, project: catalog.lookup(source.key)?.project, preparingModel: true)
        deletedSessions.insert(target.key)
        unsentSessions.started(target.key)
        catalog.remove(target.key)
        return target
    }

    func chooseAgentModel(_ row: ComposerAgentModel, for source: SessionModel, undoManager: UndoManager? = nil) {
        guard offersAgentModels, source.modelChange?.isPending != true else { return }
        let change = ComposerAgentChange(source: source, choice: row, app: self)
        source.modelChange = change
        change.start(undoManager: undoManager)
    }
}
