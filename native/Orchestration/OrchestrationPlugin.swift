import ACP
import Foundation
import MCP
import NativeHostProtocol
import NativeOrchestration
import NativePolicy
import os

/// Lets agents hand tasks to other agents, such as Claude Code asking Codex for a review. Every
/// session uses a signed local URL through the skill's CLI or MCP, so each tool call is attributed
/// to the session that made it and the tasks it starts become its subagents.
///
/// Native's host serves the tools to its own sessions (`HostTasks`, docs/durability.md, "Native's
/// tools in the host"), so delegated work goes on with the app closed and on other machines. The
/// app serves them itself only when agents run inside it, or when that setting is off: then the
/// server listens on the port it had last launch, and a session's token is signed from its stable
/// id ("Native's MCP server across launches").
struct OrchestrationPlugin: NativePlugin {
    static let id = "orchestration"
    /// The server's name in agents' MCP lists.
    nonisolated static let serverName = "native"

    let manifest = PluginManifest(
        id: Self.id,
        name: "Orchestration",
        description:
            "Lets agents hand tasks to other agents, such as Claude Code asking Codex for a review, and shows those tasks as subagents."
    )

    /// Runs the tools' tasks as the app's sessions, while the app serves them.
    let runtime: AppTaskRuntime
    /// Other features' tools for `run_script`.
    let scriptExtensions: OrchestrationScriptExtensions
    /// Whether the server offers `run_script`: only where the script runtime is.
    let hasScripts: Bool
    /// What the server's start means for the user (a move to another port, the host taking over).
    let status: OrchestrationServerStatus
    /// The tools only the app can answer (`setup_status`, and `run_script` with the host's task tools
    /// bound), which it offers the host for the sessions the host serves.
    let appOnlyTools: [MCPTool<OrchestrationCaller>]
    /// How those reach the host's own tools.
    let hostCalls: HostToolCalls
    private let server: MCPHTTPServer<OrchestrationCaller>
    private let tokens: MCPTokens

    init() {
        let runtime = AppTaskRuntime()
        let orchestrator = TaskOrchestrator(runtime: AppTaskRuntimeAdapter(base: runtime))
        let tokens = MCPTokens()
        let tools = OrchestrationTools.all(orchestrator)
        // run_script exists only where the script runtime does; without it the server just lacks it.
        let extensions = OrchestrationScriptExtensions()
        // An organization can turn the script runtime off (`policy.scripts.enabled`).
        let script =
            PolicyCenter.currentPolicy().scriptsEnabled
            ? OrchestrationScriptTool.make(binding: tools, extensions: extensions) : nil
        let setup = SetupTools.all { caller in try await runtime.setupReport(callerAgent: caller.agent) }
        // For sessions the host serves, scripts call the host's tools, which know its tasks.
        let hostCalls = HostToolCalls()
        let hostTaskTools = tools.map { tool in
            tool.forwarding { caller, arguments in await hostCalls.call(tool.name, for: caller, arguments: arguments) }
        }
        let hostScript =
            script == nil ? nil : OrchestrationScriptTool.make(binding: hostTaskTools, extensions: extensions)
        appOnlyTools = [hostScript].compactMap { $0 } + setup
        let server = MCPHTTPServer(
            name: Self.serverName,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            instructions: OrchestrationTools.instructions + (script == nil ? "" : OrchestrationScriptTool.instructions)
                + SetupTools.instructions,
            tools: tools + [script].compactMap { $0 }
                + SkillTools.all(NativeSkill.bundled(), pluginsFolder: PluginRegistry.directory) { skills, caller in
                    await orchestrator.skills(skills, for: caller)
                }
                + setup
        ) { token in
            // The token is the only credential a caller presents; nothing it didn't sign gets in.
            let policy = PolicyCenter.currentPolicy()
            guard policy.decision(for: .orchestration).isPermitted,
                policy.decision(for: .mcpExecution).isPermitted, policy.mcp.allows(name: Self.serverName),
                policy.network.isValid, policy.network.localIPC
            else { return nil }
            guard let client = tokens.client(in: token) else { return nil }
            return await runtime.caller(of: client)
        }
        self.runtime = runtime
        self.hostCalls = hostCalls
        self.scriptExtensions = extensions
        hasScripts = script != nil
        self.server = server
        self.tokens = tokens
        let status = OrchestrationServerStatus()
        self.status = status
        // Listening takes a moment, long before the first session asks for the URL; up to five seconds
        // when the copy of Native this one replaces still holds the port.
        Task {
            let channel = HostRegistration().location.channel
            do {
                let launch = try await server.start(
                    remembering: MCPServerStore(directory: Self.storeFolder(channel: channel)),
                    scope: channel, tokens: tokens)
                if let failure = launch.storeFailure {
                    Self.logger.error(
                        "Native's MCP URLs won't outlast this launch: \(failure, privacy: .public)")
                }
                status.started(launch)
            } catch {
                Self.logger.error("Couldn't start the orchestration MCP server: \(error)")
            }
        }
    }

    func mcpServers(for session: SessionContext) -> [MCPServer] {
        // The host gives the sessions it serves Native's tools at its own address.
        guard !status.isServedByHost, let url = url(for: session.clientID) else { return [] }
        if runtime.durableHost == nil, runtime.model?.plugins.nativeMCPChoice(for: session.agent) == false { return [] }
        runtime.handedURL(to: session)
        return [.http(name: Self.serverName, url: url)]
    }

    /// The URL of the session Native knows by `clientID`: the same one every launch, unless the
    /// server had to move. Nil until the server is listening.
    func url(for clientID: UUID) -> URL? {
        tokens.token(for: clientID).flatMap(server.url(for:))
    }

    /// The host serves the tools from now on, so the app's server stops: nothing reaches it, and
    /// the port it remembered is free for whoever needs it.
    func handOverToHost() {
        status.servedByHost()
        server.stop()
    }

    static let logger = Logger(subsystem: "Native", category: "Orchestration")

    /// Where the server keeps its port and token secret: the app's Application Support, per host
    /// channel, since development builds from different folders share a bundle id but not a host.
    private static func storeFolder(channel: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Native", directoryHint: .isDirectory)
            .appending(path: "Orchestration/\(channel.isEmpty ? "default" : channel)", directoryHint: .isDirectory)
    }
}

extension OrchestrationPlugin {
    /// Lets the tools run tasks as `model`'s sessions and report how Native is set up. With a host,
    /// follows who serves the tools to its sessions.
    static func connect(to model: AppModel, updates: UpdateController?, durableHost: DurableHost?) {
        guard let plugin = model.plugins.plugins.lazy.compactMap({ $0.plugin as? OrchestrationPlugin }).first else {
            return
        }
        plugin.runtime.model = model
        plugin.runtime.durableHost = durableHost
        plugin.runtime.setup = AppSetupReporter(model: model, updates: updates, durableHost: durableHost)
        if let durableHost {
            Task { await plugin.followHost(durableHost, model: model) }
        }
    }
}
