import ACP
import Foundation
import NativeHostProtocol
import Search
import SessionTitling

enum BuiltInPlugins {
    static let all: [any NativePlugin] = [
        claudeCode, codex, cursor, openCode, pi, copilot, OnDeviceTitlesPlugin(), SoundsPlugin(),
        OrchestrationPlugin(), MCPServersPlugin(), SkillsPlugin(), usage, automation, automations, expeditions, search,
        CelebrationsPlugin(),
    ]

    /// Claude Code through its ACP adapter, running the user's own `claude`. Adapter versions are
    /// pinned so upgrades are deliberate; the adapters move fast.
    static let claudeCode = ManifestPlugin(
        manifest: PluginManifest(
            id: "claude-code",
            name: "Claude Code",
            description: "Anthropic's coding agent, through the Claude Agent SDK's ACP adapter.",
            agents: [
                AgentManifest(
                    id: "claude-code",
                    name: "Claude Code",
                    symbol: "asterisk",
                    command: "npx",
                    args: ["--yes", "@agentclientprotocol/claude-agent-acp@0.93.0"],
                    resolveExecutables: ["CLAUDE_CODE_EXECUTABLE": "claude"],
                    mcpConfig: "claude-code",
                    icon: AgentIconSource(apps: ["com.anthropic.claudefordesktop"], registry: "claude-acp"),
                    requires: ["claude"],
                    setup: AgentSetupGuide(
                        install: "npm install -g @anthropic-ai/claude-code",
                        docs: URL(string: "https://code.claude.com/docs/en/setup"),
                        signIn: "claude"
                    ),
                    // Each session is its own Claude Code process with its own MCP servers (about
                    // 650 MB and 0.5% CPU idle here), and one loads back faithfully in seconds.
                    idleSessionTimeout: 600,
                    // Claude Code reads these from its environment, and its adapter lists no sign-in
                    // methods, so they're how a host nobody sits at signs it in.
                    authMethods: [
                        AuthMethod(
                            id: "anthropic-api-key", name: "Anthropic API key",
                            description: "Pay as you go with a key from the Anthropic Console.",
                            kind: .environment([AuthMethod.Variable(name: "ANTHROPIC_API_KEY", label: "API key")]),
                            credentialsPage: URL(string: "https://console.anthropic.com/settings/keys")),
                        AuthMethod(
                            id: "claude-oauth-token", name: "Claude subscription token",
                            description:
                                "Run `claude setup-token` on a computer with a browser, then paste the token it prints.",
                            kind: .environment([AuthMethod.Variable(name: "CLAUDE_CODE_OAUTH_TOKEN", label: "Token")])),
                    ]
                )
            ]
        ), policyTranslator: ClaudeCodePolicyTranslator(), historyReader: ClaudeCodeHistoryReader.standard())

    /// OpenAI's Codex CLI through its ACP adapter, running the user's own `codex`.
    static let codex = ManifestPlugin(
        manifest: PluginManifest(
            id: "codex",
            name: "Codex",
            description: "OpenAI's coding agent, through the Codex ACP adapter.",
            agents: [
                AgentManifest(
                    id: "codex",
                    name: "Codex",
                    symbol: "terminal",
                    command: "npx",
                    args: ["--yes", "@agentclientprotocol/codex-acp@2.2.2"],
                    resolveExecutables: ["CODEX_PATH": "codex"],
                    mcpConfig: "codex",
                    icon: AgentIconSource(apps: ["com.openai.codex", "com.openai.chat"], registry: "codex-acp"),
                    requires: ["codex"],
                    setup: AgentSetupGuide(
                        install: "npm install -g @openai/codex",
                        docs: URL(string: "https://developers.openai.com/codex/cli")
                    ),
                    // Every loaded session runs the user's MCP servers (half a gigabyte a task here),
                    // and closing one frees nothing for 30 minutes; ending the adapter frees it all,
                    // and a session resumes without a replay.
                    idleUnloadTimeout: 600,
                    // The adapter offers its device code only to clients that open links, so the
                    // host starts it that way for this sign-in (`AuthMethod.Kind.link`).
                    authMethods: [
                        AuthMethod(
                            id: "chat-gpt-device-code", name: "ChatGPT (device code)",
                            description:
                                "Sign in to ChatGPT by opening a verification page and entering a one-time code",
                            kind: .link)
                    ]
                )
            ]
        ), policyTranslator: CodexPolicyTranslator(), historyReader: CodexHistoryReader.standard())
}

// MARK: - Titles

/// Titles sessions with Apple's on-device model: private, free, and fast enough to name a session
/// as soon as it starts.
struct OnDeviceTitlesPlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "on-device-titles",
        name: "On-Device Titles",
        description: "Names sessions from your first prompt using Apple Intelligence on this Mac."
    )

    var titler: (any SessionTitler)? { OnDeviceTitler() }
}

/// The same model the host titles tasks with (`OnDeviceTitleGenerator`), so a title reads the same
/// whether the host or the app wrote it.
struct OnDeviceTitler: SessionTitler {
    var hostProvider: HostTitleProvider? { .onDevice }

    func title(for request: TitleRequest) async throws -> String? {
        try await OnDeviceTitleGenerator().title(
            for: SessionTitleRequest(
                projectName: request.projectName, prompt: request.prompt, instructions: request.instructions))
    }
}
