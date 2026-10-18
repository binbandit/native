import Foundation
import MCPClient

/// Native's own connections to the servers that run through scripts, opened on a script's first
/// use and kept while the server stays scripted, so later scripts don't wait for it to start.
actor MCPScriptConnections {
    /// A failed connection isn't retried for this long, so a broken server doesn't relaunch on
    /// every script.
    private static let retryAfter: Duration = .seconds(20)

    private let launcher: any StdioLauncher
    private var connections: [String: Connection] = [:]

    private enum Connection {
        case connecting(Task<Result<MCPSession, MCPSessionError>, Never>, MCPServerConfig)
        case connected(MCPSession, MCPServerConfig)
        case failed(MCPSessionError, MCPServerConfig, at: ContinuousClock.Instant)
    }

    init(launcher: any StdioLauncher) {
        self.launcher = launcher
    }

    /// The live session for `server`, connecting the first time; a changed configuration reconnects.
    func session(
        for server: MCPScriptedServer, environment: [String: String]
    ) async -> Result<MCPSession, MCPSessionError> {
        switch connections[server.key] {
        case .connected(let session, let config) where config == server.config:
            return .success(session)
        case .connecting(let task, let config) where config == server.config:
            return await task.value
        case .failed(let error, let config, let at)
        where config == server.config && ContinuousClock.now - at < Self.retryAfter:
            return .failure(error)
        case .connected(let session, _):
            Task { await session.close() }
        default:
            break
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let launcher = launcher
        let task = Task { () -> Result<MCPSession, MCPSessionError> in
            do throws(MCPSessionError) {
                return .success(
                    try await MCPSession.connect(
                        server.config, environment: environment, directory: server.directory, clientVersion: version,
                        launcher: launcher))
            } catch {
                return .failure(error)
            }
        }
        connections[server.key] = .connecting(task, server.config)
        let result = await task.value
        // Only if nothing replaced it meanwhile.
        if case .connecting(let current, _) = connections[server.key], current == task {
            switch result {
            case .success(let session): connections[server.key] = .connected(session, server.config)
            case .failure(let error): connections[server.key] = .failed(error, server.config, at: .now)
            }
        }
        return result
    }

    /// The session if it's already up, without connecting.
    func existing(for key: String) -> MCPSession? {
        if case .connected(let session, _) = connections[key] { return session }
        return nil
    }

    /// Drops a connection that stopped working, so the next use starts the server again.
    func forget(_ key: String) async {
        guard case .connected(let session, _) = connections.removeValue(forKey: key) else { return }
        await session.close()
    }

    /// Closes the connections to servers no longer in `keys`.
    func keep(only keys: Set<String>) async {
        for (key, connection) in connections where !keys.contains(key) {
            connections[key] = nil
            if case .connected(let session, _) = connection { await session.close() }
        }
    }
}
