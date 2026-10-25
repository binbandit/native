import ACP
import Foundation

/// Where a task changing agents runs, and so where its replacement may start.
enum AgentChangePlace: Equatable {
    /// In the app or this Mac's host, with this Mac's agents.
    case thisMac
    /// On a paired host, through the client its current pairing holds.
    case host(RemoteHostID)
    /// On a paired host no current pairing reaches (removed, ended, or paired again with another
    /// key): nothing may start for the task anywhere until it's reachable again.
    case unavailable
}

// Change Agent for a task on a paired host (ChangeAgent/AppModel+ChangeAgent.swift). The task's own
// host is the only place it continues: the replacement is one of that host's agents, started there
// in the task's folder. Nothing is cloned, no worktree is made and nothing runs on this Mac, and the
// host's listing, not this Mac's catalog or its unsent drafts, publishes the replacement.
extension AppModel {
    func agentChangePlace(of session: SessionModel) -> AgentChangePlace {
        guard let link = session.host, link.client !== runtimes.host else { return .thisMac }
        return hosts.all.first { $0.client === link.client }.map { .host($0.id) } ?? .unavailable
    }

    /// The agents a task at `place` can continue with: this Mac's, or only its host's.
    func agentChangeRuntimes(at place: AgentChangePlace) -> [AgentRuntime] {
        switch place {
        case .thisMac:
            return agents
        case .host(let id):
            guard offersRemoteHosts, let host = hosts.host(id), let client = host.client else { return [] }
            return host.runtimes.filter { $0.host === client }
        case .unavailable:
            return []
        }
    }

    /// Why a paired host's task can't change agents now; nil for this Mac's tasks.
    func remoteAgentChangeBlock(for source: SessionModel) -> String? {
        let place = agentChangePlace(of: source)
        guard place != .thisMac else { return nil }
        guard offersRemoteHosts, case .host(let id) = place, let host = hosts.host(id) else {
            return "Reconnect the task's host in Settings > Hosts to change its agent."
        }
        guard host.isOnline else { return "Reconnect \(host.name) to change this task's agent." }
        return nil
    }

    /// `agent` where the task runs, started if it's idle; nil when it can't start, with
    /// `agentChangeStartFailure(of:at:)` saying why.
    func startAgentChangeRuntime(_ agent: AgentDefinition.ID, at place: AgentChangePlace) async -> AgentRuntime? {
        guard place != .thisMac else { return await ensureRunning(agent) }
        func current() -> AgentRuntime? { agentChangeRuntimes(at: place).first { $0.agent.id == agent } }
        guard let runtime = current(), runtime.isAvailable else { return nil }
        if !runtime.isReady { await runtime.startOnHost() }
        // Pairing the host again meanwhile gives it runtimes of its own, on the client the task has now.
        return current().flatMap { $0.isReady ? $0 : nil }
    }

    func agentChangeStartFailure(of agent: AgentDefinition.ID, at place: AgentChangePlace) -> String {
        guard case .host(let id) = place else {
            return place == .thisMac
                ? startFailure(of: agent) : "Reconnect the task's host in Settings > Hosts to change its agent."
        }
        guard let host = hosts.host(id), let runtime = host.runtime(agent) else {
            return "That agent isn't available on the task's host anymore. Choose another agent."
        }
        let reason = runtime.status.guidance ?? runtime.status.label
        return "Couldn't start \(runtime.agent.displayName) on \(host.name): \(reason)"
    }

    /// Lists an accepted replacement as its host lists it, in the task's checkout there.
    func publishRemoteAgentChange(_ target: SessionModel, in project: Project.ID) {
        deletedSessions.remove(target.key)
        if let project = projects.project(project) { rememberRemoteWorkspace(of: target, in: project) }
        indexRemoteSessions()
    }
}
