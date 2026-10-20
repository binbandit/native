import ACP
import Foundation
import MCP
import NativeHostProtocol
import NativePolicy
import os

/// Lets agents hand tasks to other agents, such as Claude Code asking Codex for a review. Every
/// session gets Native's MCP server at a URL only it knows, so each tool call is attributed to the
/// session that made it and the tasks it starts become its subagents.
///
/// Sessions in Native's host outlive the app and keep the URL they were first given, so the URL
/// does too: the server listens on the port it had last launch, and a session's token is signed
/// from its stable id (`docs/durability.md`, "Native's MCP server across launches").
struct OrchestrationPlugin: NativePlugin {
    static let id = "orchestration"
    /// The server's name in agents' MCP lists.
    static let serverName = "native"

    let manifest = PluginManifest(
        id: Self.id,
        name: "Orchestration",
        description:
            "Lets agents hand tasks to other agents, such as Claude Code asking Codex for a review, and shows those tasks as subagents."
    )

    /// Set its `host` to let the tools run tasks.
    let orchestrator: Orchestrator
    /// Other features' tools for `run_script`.
    let scriptExtensions: OrchestrationScriptExtensions
    /// Whether the server offers `run_script`: only where the script runtime is.
    let hasScripts: Bool
    /// What the server's start means for the user (a move to another port), for the notice.
    let status: OrchestrationServerStatus
    private let server: MCPHTTPServer<OrchestrationCaller>
    private let tokens: MCPTokens

    init() {
        let orchestrator = Orchestrator()
        let tokens = MCPTokens()
        let tools = OrchestrationTools.all(orchestrator)
        // run_script exists only where the script runtime does; without it the server just lacks it.
        let extensions = OrchestrationScriptExtensions()
        // An organization can turn the script runtime off (`policy.scripts.enabled`).
        let script =
            PolicyCenter.currentPolicy().scriptsEnabled
            ? OrchestrationScriptTool.make(binding: tools, extensions: extensions) : nil
        let server = MCPHTTPServer(
            name: Self.serverName,
            version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
            instructions: OrchestrationTools.instructions + (script == nil ? "" : OrchestrationScriptTool.instructions)
                + SetupTools.instructions,
            tools: tools + [script].compactMap { $0 }
                + SkillTools.all(NativeSkill.bundled(), pluginsFolder: PluginRegistry.directory) { skills, caller in
                    await orchestrator.skills(skills, for: caller)
                }
                + SetupTools.all { caller in try await orchestrator.setupReport(for: caller) }
        ) { token in
            // The token is the only credential a caller presents; nothing it didn't sign gets in.
            guard let client = tokens.client(in: token) else { return nil }
            return await orchestrator.caller(of: client)
        }
        self.orchestrator = orchestrator
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
        guard let url = url(for: session.clientID) else { return [] }
        orchestrator.handedURL(to: session)
        return [.http(name: Self.serverName, url: url)]
    }

    /// The URL of the session Native knows by `clientID`: the same one every launch, unless the
    /// server had to move. Nil until the server is listening.
    func url(for clientID: UUID) -> URL? {
        tokens.token(for: clientID).flatMap(server.url(for:))
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
