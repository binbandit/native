import ACP
import Foundation
import MCP
import os

/// Lets agents hand tasks to other agents, such as Claude Code asking Codex for a review. Every
/// session gets Native's MCP server at a URL only it knows, so each tool call is attributed to the
/// session that made it and the tasks it starts become its subagents.
struct OrchestrationPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "orchestration",
        name: "Orchestration",
        description: "Lets agents hand tasks to other agents, such as Claude Code asking Codex for a review, and shows those tasks as subagents."
    )

    /// Set its `host` to let the tools run tasks.
    let orchestrator: Orchestrator
    /// Other features' tools for `run_script`.
    let scriptExtensions: OrchestrationScriptExtensions
    /// Whether the server offers `run_script`: only where the script runtime is.
    let hasScripts: Bool
    private let server: MCPHTTPServer<OrchestrationCaller>

    init() {
        let orchestrator = Orchestrator()
        let tools = OrchestrationTools.all(orchestrator)
        // run_script exists only where the script runtime does; without it the server just lacks it.
        let extensions = OrchestrationScriptExtensions()
        // An organization can turn the script runtime off (`policy.scripts.enabled`).
        let script =
            PolicyCenter.currentPolicy().scriptsEnabled
            ? OrchestrationScriptTool.make(binding: tools, extensions: extensions) : nil
        let server = MCPHTTPServer(
            name: "native",
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            instructions: OrchestrationTools.instructions + (script == nil ? "" : OrchestrationScriptTool.instructions),
            tools: tools + [script].compactMap { $0 }
                + SkillTools.all(NativeSkill.bundled(), pluginsFolder: PluginRegistry.directory)
        ) { token in
            await orchestrator.caller(for: token)
        }
        self.orchestrator = orchestrator
        self.scriptExtensions = extensions
        hasScripts = script != nil
        self.server = server
        // Listening takes a moment, long before the first session asks for the URL.
        Task {
            do {
                try await server.start()
            } catch {
                Logger(subsystem: "Native", category: "Orchestration").error("Couldn't start the orchestration MCP server: \(error)")
            }
        }
    }

    func mcpServers(for session: SessionContext) -> [MCPServer] {
        guard let url = server.url(for: orchestrator.token(for: session)) else { return [] }
        return [.http(name: "native", url: url)]
    }
}
