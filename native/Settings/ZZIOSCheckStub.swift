import Foundation

// The real built-ins' manifests (BuiltInPlugins.swift pulls in Orchestration).
enum BuiltInPlugins {
    static let all: [any NativePlugin] = [
        ManifestPlugin(manifest: PluginManifest(id: "claude-code", name: "Claude Code", description: "Anthropic's coding agent, through the Claude Agent SDK's ACP adapter.", agents: [AgentManifest(id: "claude-code", name: "Claude Code", symbol: "asterisk", command: "npx", args: ["--yes", "@agentclientprotocol/claude-agent-acp@0.93.0"], resolveExecutables: ["CLAUDE_CODE_EXECUTABLE": "claude"])])),
        ManifestPlugin(manifest: PluginManifest(id: "codex", name: "Codex", description: "OpenAI's coding agent, through the Codex ACP adapter.", agents: [AgentManifest(id: "codex", name: "Codex", symbol: "terminal", command: "npx", args: ["--yes", "@agentclientprotocol/codex-acp@2.2.2"], resolveExecutables: ["CODEX_PATH": "codex"])])),
        ManifestPlugin(manifest: PluginManifest(id: "cursor", name: "Cursor", description: "Cursor's coding agent, through the Cursor CLI's built-in ACP server.", agents: [AgentManifest(id: "cursor", name: "Cursor", symbol: "cursorarrow", command: "cursor-agent", args: ["acp"])])),
        TitlesStub(),
        ManifestPlugin(manifest: PluginManifest(id: "notifications", name: "Notifications", description: "Notifies you when a session finishes or needs your approval while Native is in the background.")),
        ManifestPlugin(manifest: PluginManifest(id: "orchestration", name: "Orchestration", description: "Gives agents tools to start and message other sessions.", mcpServers: [MCPServerManifest(name: "native", url: URL(string: "http://127.0.0.1:0"))])),
    ]
}

struct TitlesStub: NativePlugin {
    let manifest = PluginManifest(id: "on-device-titles", name: "On-Device Titles", description: "Names sessions from your first prompt using Apple Intelligence on this Mac.")
    var titler: (any SessionTitler)? { Stub() }
    struct Stub: SessionTitler { func title(for request: TitleRequest) async throws -> String? { nil } }
}
