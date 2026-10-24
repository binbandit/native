import ACP
import Foundation
import MCPClient

extension MCPLibrary {
    /// Reports younger than this are reused rather than probed again when a list opens.
    static let freshness: Duration = .seconds(300)
    /// Probes at once, at most: each local server is a process.
    static let probeLimit = 4

    func isProbing(_ key: MCPServerKey) -> Bool {
        probing.contains(key)
    }

    /// Connects to the server, initializes and lists its tools, then disconnects. Never calls a
    /// tool. The report replaces any earlier one.
    func probe(_ key: MCPServerKey, in session: SessionContext? = nil) async {
        guard !probing.contains(key), let host else { return }
        probing.insert(key)
        defer { probing.remove(key) }
        if case .agent = key { await readConfigurationsIfStale() }
        let environment = await host.mcpEnvironment()
        guard let (config, directory) = target(of: key, environment: environment, session: session) else { return }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let probe = MCPProbe(clientVersion: version, launcher: launcher)
        reports[key] = await probe.probe(config, environment: environment, directory: directory)
    }

    /// Probes every server that loads somewhere: managed ones that are on, and agents' own that
    /// aren't turned off. A few at a time.
    func probeAll() async {
        let keys =
            servers.filter { mode(of: $0.transport.endpoint.key, in: nil) == .on }.map { MCPServerKey.managed($0.id) }
            + configurations.values.flatMap(\.servers).filter { $0.status != .disabled }.map {
                MCPServerKey.agent($0.id)
            }
        await probe(keys)
    }

    /// Probes a session's active servers that haven't been checked in the last few minutes.
    func probeStale(_ entries: [MCPSessionEntry], in session: SessionContext) async {
        let stale = entries.filter(\.isActive).map(\.key).filter { key in
            reports[key].map { Date.now.timeIntervalSince($0.startedAt) > Double(Self.freshness.components.seconds) }
                ?? true
        }
        await probe(stale, in: session)
    }

    private func probe(_ keys: [MCPServerKey], in session: SessionContext? = nil) async {
        await withTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                if index >= Self.probeLimit { await group.next() }
                group.addTask { await self.probe(key, in: session) }
            }
        }
    }

    /// The configuration to probe and the folder to start a local server in.
    private func target(
        of key: MCPServerKey, environment: [String: String], session: SessionContext?
    ) -> (MCPServerConfig, String?)? {
        let home = environment["HOME"]
        switch key {
        case .managed(let id):
            guard let server = server(id) else { return nil }
            return (server.config(with: secrets(for: id)), session.map { ProjectPath.key($0.cwd) } ?? home)
        case .agent(let id):
            guard let entry = configuredServer(for: .agent(id)) else {
                return nil
            }
            let project = entry.scope.project ?? session?.cwd
            return (entry.resolved(environment: environment, project: project), project.map(ProjectPath.key) ?? home)
        case .plugin(let id):
            guard let server = host?.mcpPluginServers(for: session).first(where: { $0.id == id }) else { return nil }
            return (server.config, home)
        }
    }

    // MARK: - Status

    /// Where a server stands, in the one vocabulary every MCP view uses.
    func health(of key: MCPServerKey, inactive reason: String? = nil) -> MCPHealth {
        MCPHealth(
            report: reports[key], authentication: configuredServer(for: key)?.authentication,
            isChecking: probing.contains(key), inactiveReason: reason)
    }

    /// Tokens Claude Code counts for a server's tools: in `session`'s latest `/context` report, or
    /// the newest report that lists the server when no session is given.
    func contextCost(of name: String, in session: SessionKey? = nil) -> MCPContextCost? {
        let reports = host?.mcpContextReports ?? [:]
        let candidates = session.map { key in reports[key].map { [$0] } ?? [] } ?? Array(reports.values)
        return
            candidates
            .sorted { $0.capturedAt > $1.capturedAt }
            .lazy
            .compactMap { report in
                report.mcpServers.first { $0.name == name }.map {
                    MCPContextCost(
                        tokens: $0.tokens, tools: $0.tools.count, window: report.windowTokens,
                        capturedAt: report.capturedAt)
                }
            }
            .first
    }

    /// Whether a session's `/context` report shows the server's tools loaded. Nil without a report,
    /// or when the agent defers some MCP tools (deferred ones aren't listed by server).
    func isLoaded(_ name: String, in session: SessionKey) -> Bool? {
        guard let report = host?.mcpContextReports[session] else { return nil }
        if report.mcpServers.contains(where: { $0.name == name }) { return true }
        let hasDeferred = report.deferredCategories.contains { $0.name.localizedCaseInsensitiveContains("mcp") }
        return hasDeferred ? nil : false
    }
}

/// A server's share of an agent's context window, from the agent's own report.
struct MCPContextCost: Hashable {
    let tokens: Int
    let tools: Int
    let window: Int
    let capturedAt: Date

    var fraction: Double {
        window > 0 ? Double(tokens) / Double(window) : 0
    }
}
