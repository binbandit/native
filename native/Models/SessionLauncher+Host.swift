import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

// Starting and opening sessions in Native's host (`HostSessions`). The client picks the session's
// id, so plugins can key per-session resources (MCP servers) by it before the session exists; the
// host keeps those servers and hands them over again whenever it reloads the session.
extension SessionLauncher {
    /// Starts a session on an agent in the host and registers its model, following its events from
    /// the first one.
    func startOnHost(
        _ client: NativeHostClient, on runtime: AgentRuntime, cwd: URL, origin: SessionModel.Origin,
        parent: SessionModel?
    ) async throws -> SessionModel {
        let id = HostSessionID()
        let context = SessionContext(
            clientID: id.rawValue, agent: runtime.agent.id, agentName: runtime.agent.displayName, sessionID: nil,
            cwd: cwd, parentID: parent?.id)
        let summary = try await client.newSession(
            NewSessionParams(
                sessionID: id, agentID: runtime.agent.id.rawValue, cwd: cwd.folderPath, parentID: parent?.host?.id,
                origin: origin.host, mcpServers: try mcpServers(for: context, on: client), meta: meta(for: context),
                attach: true))
        guard let agentSessionID = summary.agentSessionID else {
            throw LaunchError.failed(
                agent: runtime.agent.displayName, underlying: HostTurnFailure(message: "No session"))
        }
        let session = SessionModel(
            agent: runtime.agent, id: agentSessionID, summary: summary, client: client, services: services,
            promptCapabilities: runtime.capabilities?.prompt ?? PromptCapabilities(), origin: origin, parent: parent)
        store.register(session)
        return session
    }

    /// Opens a session the agent listed, or the host already has open, and registers its model. It
    /// comes back loading, with the agent's replay streaming in; a load that fails says so in its
    /// transcript.
    func openOnHost(
        _ client: NativeHostClient, _ key: SessionKey, cwd: URL, title: String?, on runtime: AgentRuntime,
        origin: SessionModel.Origin, parent: SessionModel?
    ) async throws -> SessionModel {
        if let opening = hostOpens[key] {
            return try await opening.value
        }
        let opening = Task {
            try await performOpen(client, key, cwd: cwd, title: title, on: runtime, origin: origin, parent: parent)
        }
        hostOpens[key] = opening
        defer { hostOpens[key] = nil }
        return try await opening.value
    }

    private func performOpen(
        _ client: NativeHostClient, _ key: SessionKey, cwd: URL, title: String?, on runtime: AgentRuntime,
        origin: SessionModel.Origin, parent: SessionModel?
    ) async throws -> SessionModel {
        // A session the host already has keeps its id and the servers it was first opened with, so
        // plugins key what they hand the agent by that id: it's the one the agent's servers know.
        let id = await openHostSessionID(of: key, on: client) ?? HostSessionID()
        let context = SessionContext(
            clientID: id.rawValue, agent: runtime.agent.id, agentName: runtime.agent.displayName, sessionID: key.id,
            cwd: cwd, title: title, parentID: parent?.id)
        let summary = try await client.openSession(
            OpenSessionParams(
                sessionID: id, agentID: runtime.agent.id.rawValue, agentSessionID: key.id, cwd: cwd.folderPath,
                title: title, parentID: parent?.host?.id, origin: origin.host,
                mcpServers: try mcpServers(for: context, on: client), meta: meta(for: context), attach: true,
                configChoices: services.titles.configChoices(for: .init(agent: key.agent, session: key.id))
                    .choices.mapValues(\.value),
                configDefaults: AgentSessionDefaults.configuredValues(for: key.agent)))
        let session = SessionModel(
            agent: runtime.agent, id: key.id, summary: summary, client: client, services: services,
            promptCapabilities: runtime.capabilities?.prompt ?? PromptCapabilities(), origin: origin, parent: parent)
        if session.state.title == nil, let title {
            session.state.title = title
        }
        store.register(session)
        return session
    }

    /// The id of the host session holding `key`, if the host has one open: from what it last said,
    /// or by asking.
    private func openHostSessionID(of key: SessionKey, on client: NativeHostClient) async -> HostSessionID? {
        func holding(_ summary: HostSessionSummary) -> Bool {
            summary.agentID == key.agent.rawValue && summary.agentSessionID == key.id
        }
        if let summary = store.hostSummaries.values.first(where: holding) {
            return summary.id
        }
        return (try? await client.sessions())?.first(where: holding)?.id
    }

    /// Plugins' MCP servers for the session, as the JSON the host hands the agent. A paired host
    /// gets only the ones it can reach itself (`PairedHostServers`).
    private func mcpServers(for context: SessionContext, on client: NativeHostClient) throws -> [JSONValue] {
        let servers = try JSONDecoder().decode(
            [JSONValue].self, from: JSONEncoder().encode(plugins.mcpServers(for: context)))
        return isRemote(client) ? PairedHostServers.reachable(servers) : servers
    }

    private func meta(for context: SessionContext) -> JSONValue? {
        let meta = plugins.sessionMeta(for: context)
        return meta.isEmpty ? nil : .object(meta)
    }
}

extension SessionModel.Origin {
    /// The same origin, as the host protocol names it.
    var host: SessionOrigin {
        switch self {
        case .user: .user
        case .task: .task
        case .announced: .announced
        }
    }
}
