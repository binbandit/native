import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

/// Creates session models on agents: asks the agent for the session with plugins' MCP servers,
/// builds the model and registers it so the agent's events reach it. For an agent in Native's host,
/// the host starts or opens the session (SessionLauncher+Host.swift).
final class SessionLauncher {
    enum LaunchError: LocalizedError {
        case parentClosed
        case agentUnavailable(String)
        /// The agent lists its past sessions but can't load one (no `loadSession` capability).
        case cannotLoad(String)
        case failed(agent: String, underlying: any Error)

        var errorDescription: String? {
            switch self {
            case .parentClosed: "The session that asked for this is no longer open."
            case .agentUnavailable(let agent): "\(agent) isn't running, so it can't start a session."
            case .cannotLoad(let agent): "\(agent) can't reopen its past sessions."
            case .failed(let agent, let underlying):
                "Couldn't start a \(agent) session: \(underlying.localizedDescription)"
            }
        }
    }

    let plugins: PluginRegistry
    let services: SessionServices
    let store: SessionStore
    /// Host sessions being opened, so a second caller (selecting a row opens it from two places)
    /// gets the same model rather than a second one (SessionLauncher+Host.swift).
    var hostOpens: [SessionKey: Task<SessionModel, any Error>] = [:]
    /// Whether a client reaches a paired host rather than this Mac's own (AppModel+Hosts.swift).
    var isRemote: (NativeHostClient) -> Bool = { _ in false }

    init(plugins: PluginRegistry, services: SessionServices, store: SessionStore) {
        self.plugins = plugins
        self.services = services
        self.store = store
    }

    /// Starts a session in `cwd`, on what new sessions in `project` start on (`AgentSessionDefaults`).
    /// A task session's `parent` adopts it as a subagent. `earlier` is the conversation a user's task
    /// carries on from (`/clear`). The agent's error comes through as is, so callers can tell when it
    /// wants the user to sign in.
    func start(
        on runtime: AgentRuntime, cwd: URL, project: Project.ID?, origin: SessionModel.Origin = .user,
        parent: SessionModel? = nil, continuing earlier: SessionModel? = nil
    ) async throws -> SessionModel {
        if let host = runtime.host {
            let session = try await startOnHost(
                host, on: runtime, cwd: cwd, origin: origin, parent: parent)
            return await prepare(
                session, on: runtime, project: project, origin: origin, parent: parent, earlier: earlier)
        }
        guard let connection = runtime.localConnection else {
            throw LaunchError.agentUnavailable(runtime.agent.displayName)
        }
        // Plugins key per-session resources by Native's own id, since the agent's doesn't exist yet.
        let clientID = UUID()
        let context = SessionContext(
            clientID: clientID, agent: runtime.agent.id, agentName: runtime.agent.displayName,
            sessionID: nil, cwd: cwd, parentID: parent?.id
        )
        let request = NewSessionRequest(
            cwd: cwd.folderPath, mcpServers: plugins.mcpServers(for: context), meta: plugins.sessionMeta(for: context)
        )
        let response = try await connection.send(request)
        let session = SessionModel(
            agent: runtime.agent, id: response.sessionId, clientID: clientID, cwd: cwd, connection: connection,
            services: services, supportsSteering: runtime.capabilities?.steering == true,
            promptCapabilities: runtime.capabilities?.prompt ?? PromptCapabilities(), phase: .idle,
            configOptions: response.configOptions ?? [], origin: origin, parent: parent
        )
        store.register(session)
        return await prepare(session, on: runtime, project: project, origin: origin, parent: parent, earlier: earlier)
    }

    /// Gets a session that just started ready for its first prompt: the settings it starts on, then
    /// what the task starts in.
    private func prepare(
        _ session: SessionModel, on runtime: AgentRuntime, project: Project.ID?, origin: SessionModel.Origin,
        parent: SessionModel?, earlier: SessionModel?
    ) async -> SessionModel {
        AgentSessionDefaults.remember(session.state.configOptions, for: runtime.agent.id, isNew: true)
        await AgentSessionDefaults.apply(to: session, project: project)
        if origin == .user, parent == nil {
            // After the defaults, so what the task starts in (its mode) wins over them.
            await services.hooks.taskStarted(session, earlier)
        }
        services.post(.sessionStarted(session.context))
        return session
    }

    /// Reopens a session the agent has, replaying its history into a new model and setting back the
    /// settings chosen for it. On failure the model stays registered with what went wrong in its
    /// transcript, and the error is rethrown.
    @discardableResult
    func load(
        _ key: SessionKey, cwd: URL, title: String? = nil, on runtime: AgentRuntime,
        origin: SessionModel.Origin = .user, parent: SessionModel? = nil
    ) async throws -> SessionModel {
        if let host = runtime.host {
            guard runtime.capabilities?.loadSession == true else {
                throw LaunchError.cannotLoad(runtime.agent.displayName)
            }
            do {
                return try await openOnHost(
                    host, key, cwd: cwd, title: title, on: runtime, origin: origin, parent: parent)
            } catch {
                runtime.noteSignInRequired(by: error)
                throw error
            }
        }
        guard let connection = runtime.localConnection else {
            throw LaunchError.agentUnavailable(runtime.agent.displayName)
        }
        guard runtime.capabilities?.loadSession == true else {
            throw LaunchError.cannotLoad(runtime.agent.displayName)
        }
        let session = SessionModel(
            agent: runtime.agent, id: key.id, cwd: cwd, connection: connection, services: services,
            supportsSteering: runtime.capabilities?.steering == true,
            promptCapabilities: runtime.capabilities?.prompt ?? PromptCapabilities(), phase: .loading, title: title,
            origin: origin, parent: parent
        )
        store.register(session)
        do {
            let request = LoadSessionRequest(
                sessionId: key.id, cwd: cwd.folderPath, mcpServers: plugins.mcpServers(for: session.context),
                meta: plugins.sessionMeta(for: session.context)
            )
            let response = try await connection.send(request)
            await session.finishLoading(configOptions: response.configOptions)
            return session
        } catch {
            runtime.noteSignInRequired(by: error)
            session.failLoading(error)
            throw error
        }
    }
}
