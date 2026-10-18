import ACP
import Foundation
import MCPClient

/// What the MCP feature needs from the app, so it depends on this rather than on the app model's
/// internals. `AppMCPHost` provides it for `AppModel`.
protocol MCPLibraryHost: AnyObject {
    /// The agents whose own MCP configuration Native can read, in plugin order.
    var mcpAgents: [MCPAgent] { get }
    /// The open projects, whose project-scoped configuration is read.
    var mcpProjects: [URL] { get }
    /// The user's login-shell environment on the host, which local servers launch with.
    func mcpEnvironment() async -> [String: String]
    /// Claude Code's latest `/context` reports, by session: the real context cost of each server.
    var mcpContextReports: [SessionKey: ContextReport] { get }
    /// Servers other plugins hand a session (Orchestration's `native`), or every session when nil.
    func mcpPluginServers(for session: SessionContext?) -> [MCPPluginServer]
    /// How `agent` applies switches: per session, at launch, or not at all.
    func mcpPolicySupport(for agent: AgentDefinition.ID) -> SessionPolicySupport
    /// Agents still running with switches older than the current ones.
    var mcpAgentsAwaitingRestart: [MCPAgent] { get }
    /// Restarts those agents: only idle ones, unless `force`.
    func mcpApplyLaunchPolicies(force: Bool) async
    /// The session (by `SessionContext.clientID`) a script's calls are made for.
    func mcpScriptSession(_ clientID: UUID) -> MCPScriptSessionLink?
}

/// What a script's calls need from the session they're made for: whether it asks before tool
/// calls, its transcript and its approval card.
@MainActor protocol MCPScriptSessionLink {
    /// Whether its agent runs tool calls without asking in its current mode.
    var approvesToolCallsUnasked: Bool { get }
    /// The agent's run_script call still running, which the script's calls belong under.
    var runningScriptCall: String? { get }
    func record(_ call: ToolCallUpdate)
    func requestApproval(
        for call: ToolCallUpdate, options: [PermissionOption], until deadline: ContinuousClock.Instant
    ) async -> PermissionOption?
}

/// An agent whose own MCP configuration Native can read.
struct MCPAgent: Identifiable, Hashable {
    let id: AgentDefinition.ID
    let name: String
    let symbol: String
    let format: AgentConfigFormat
    /// What it advertised in `initialize`; nil while it isn't running.
    let transports: MCPTransportSupport?
    let isRunning: Bool
}

/// A server another plugin contributes, as the MCP pages list it.
struct MCPPluginServer: Hashable, Identifiable {
    let pluginName: String
    let server: MCPServer

    var name: String {
        switch server {
        case .stdio(let name, _, _, _), .http(let name, _, _): name
        }
    }

    var id: String { "\(pluginName)|\(name)" }

    var config: MCPServerConfig {
        switch server {
        case .stdio(let name, let command, let arguments, let environment):
            MCPServerConfig(
                name: name, transport: .stdio(command: command, arguments: arguments, environment: environment))
        case .http(let name, let url, let headers):
            MCPServerConfig(name: name, transport: .http(url: url, headers: headers))
        }
    }
}

/// `AppModel` as the MCP feature's host.
final class AppMCPHost: MCPLibraryHost {
    /// Weak because the model owns the plugins, which own the library, which holds this.
    private weak var model: AppModel?
    private let contextReports: @MainActor () -> [SessionKey: ContextReport]

    init(model: AppModel, contextReports: @escaping @MainActor () -> [SessionKey: ContextReport]) {
        self.model = model
        self.contextReports = contextReports
    }

    var mcpAgents: [MCPAgent] {
        (model?.agents ?? []).compactMap { runtime in
            guard let format = runtime.agent.manifest.mcpConfig.flatMap(AgentConfigFormat.init(rawValue:)) else {
                return nil
            }
            let transports = runtime.capabilities.map { MCPTransportSupport(http: $0.mcpHTTP, sse: $0.mcpSSE) }
            return MCPAgent(
                id: runtime.agent.id, name: runtime.agent.displayName, symbol: runtime.agent.symbolName, format: format,
                transports: transports, isRunning: runtime.isReady)
        }
    }

    var mcpProjects: [URL] {
        model?.projects.all.map(\.url) ?? []
    }

    func mcpEnvironment() async -> [String: String] {
        await model?.shellEnvironment() ?? [:]
    }

    var mcpContextReports: [SessionKey: ContextReport] {
        contextReports()
    }

    func mcpPolicySupport(for agent: AgentDefinition.ID) -> SessionPolicySupport {
        model?.plugins.policyTranslator(for: agent)?.support(for: .mcpServers)
            ?? .unsupported("Native has no way to turn this agent's servers off.")
    }

    var mcpAgentsAwaitingRestart: [MCPAgent] {
        let pending = Set(model?.agentsWithPendingLaunchPolicy.map(\.agent.id) ?? [])
        return mcpAgents.filter { pending.contains($0.id) }
    }

    func mcpApplyLaunchPolicies(force: Bool) async {
        await model?.applyLaunchPolicies(force: force)
    }

    func mcpScriptSession(_ clientID: UUID) -> MCPScriptSessionLink? {
        guard let model, let session = model.session(clientID: clientID) else { return nil }
        return AppMCPScriptSession(session: session, translator: model.plugins.policyTranslator(for: session.agent.id))
    }

    func mcpPluginServers(for session: SessionContext?) -> [MCPPluginServer] {
        guard let registry = model?.plugins else { return [] }
        return registry.plugins.filter { registry.isEnabled($0.id) && !($0.plugin is MCPServersPlugin) }.flatMap {
            loaded in
            let manifest = loaded.plugin.manifest
            let dynamic = session.map { loaded.plugin.mcpServers(for: $0) } ?? []
            return (manifest.mcpServers.compactMap(\.server) + dynamic).map {
                MCPPluginServer(pluginName: manifest.name, server: $0)
            }
        }
    }
}

/// A session of the app as the target of a script's calls.
private struct AppMCPScriptSession: MCPScriptSessionLink {
    let session: SessionModel
    let translator: (any SessionPolicyTranslator)?

    var approvesToolCallsUnasked: Bool {
        guard let mode = session.permissionMode else { return false }
        return translator?.approvesToolCallsUnasked(inMode: mode) ?? false
    }

    var runningScriptCall: String? {
        session.runningToolCall(named: "run_script")
    }

    func record(_ call: ToolCallUpdate) {
        session.recordNativeToolCall(call)
    }

    func requestApproval(
        for call: ToolCallUpdate, options: [PermissionOption], until deadline: ContinuousClock.Instant
    ) async -> PermissionOption? {
        await session.requestNativeApproval(for: call, options: options, until: deadline)
    }
}
