import ACP
import Foundation

/// Creates session models on agents: asks the agent for the session with plugins' MCP servers,
/// builds the model and registers it so the agent's events reach it.
final class SessionLauncher {
    enum LaunchError: LocalizedError {
        case parentClosed
        case agentUnavailable(String)
        case failed(agent: String, underlying: any Error)

        var errorDescription: String? {
            switch self {
            case .parentClosed: "The session that asked for this is no longer open."
            case .agentUnavailable(let agent): "\(agent) isn't running, so it can't start a session."
            case .failed(let agent, let underlying): "Couldn't start a \(agent) session: \(underlying.localizedDescription)"
            }
        }
    }

    private let plugins: PluginRegistry
    private let services: SessionServices
    private let store: SessionStore

    init(plugins: PluginRegistry, services: SessionServices, store: SessionStore) {
        self.plugins = plugins
        self.services = services
        self.store = store
    }

    /// Starts a session in `cwd`. A task session's `parent` adopts it as a subagent. The agent's
    /// error comes through as is, so callers can tell when it wants the user to sign in.
    func start(
        on runtime: AgentRuntime, cwd: URL, origin: SessionModel.Origin = .user, parent: SessionModel? = nil
    ) async throws -> SessionModel {
        guard let connection = runtime.connection else {
            throw LaunchError.agentUnavailable(runtime.agent.displayName)
        }
        // Plugins key per-session resources by Native's own id, since the agent's doesn't exist yet.
        let clientID = UUID()
        let context = SessionContext(
            clientID: clientID, agent: runtime.agent.id, agentName: runtime.agent.displayName,
            sessionID: nil, cwd: cwd, parentID: parent?.id
        )
        let request = NewSessionRequest(cwd: cwd.folderPath, mcpServers: plugins.mcpServers(for: context))
        let response = try await connection.send(request)
        let session = SessionModel(
            agent: runtime.agent, id: response.sessionId, clientID: clientID, cwd: cwd, connection: connection,
            services: services, supportsSteering: runtime.capabilities?.steering == true, phase: .idle,
            configOptions: response.configOptions ?? [], origin: origin, parent: parent
        )
        store.register(session)
        await AgentSessionDefaults.apply(to: session)
        services.post(.sessionStarted(session.context))
        return session
    }

    /// Reopens a session the agent has, replaying its history into a new model. On failure the
    /// model stays registered with what went wrong in its transcript, and the error is rethrown.
    @discardableResult
    func load(
        _ key: SessionKey, cwd: URL, title: String? = nil, on runtime: AgentRuntime,
        origin: SessionModel.Origin = .user, parent: SessionModel? = nil
    ) async throws -> SessionModel {
        guard let connection = runtime.connection else {
            throw LaunchError.agentUnavailable(runtime.agent.displayName)
        }
        guard runtime.capabilities?.loadSession == true else {
            throw LaunchError.failed(agent: runtime.agent.displayName, underlying: CocoaError(.featureUnsupported))
        }
        let session = SessionModel(
            agent: runtime.agent, id: key.id, cwd: cwd, connection: connection, services: services,
            supportsSteering: runtime.capabilities?.steering == true, phase: .loading, title: title,
            origin: origin, parent: parent
        )
        store.register(session)
        do {
            let request = LoadSessionRequest(sessionId: key.id, cwd: cwd.folderPath, mcpServers: plugins.mcpServers(for: session.context))
            let response = try await connection.send(request)
            session.finishLoading(configOptions: response.configOptions)
            return session
        } catch {
            runtime.noteSignInRequired(by: error)
            session.failLoading(error)
            throw error
        }
    }
}
