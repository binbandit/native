import ACP
import AIInstructions
import Foundation
import FoundationModels
import Search

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
                    idleSessionTimeout: 600
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
                    )
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

struct OnDeviceTitler: SessionTitler {
    @Generable
    struct Title {
        @Guide(
            description:
                "A 2 to 6 word title naming the task the user asked for, in sentence case, like a short commit subject. Imperative when the user asked for a change (\"Add docstring to greet\"), a noun phrase for questions (\"Auth middleware overview\"). No quotes, no trailing punctuation, no filler like \"task\" or \"request\"."
        )
        var title: String
    }

    func title(for request: TitleRequest) async throws -> String? {
        guard SystemLanguageModel.default.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: SessionTitlePrompt.instructions(adding: request.instructions))
        let response = try await session.respond(
            to: SessionTitlePrompt.prompt(projectName: request.projectName, request: request.prompt),
            generating: Title.self
        )
        let title = response.content.title
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard let first = title.first else { return nil }
        return first.uppercased() + title.dropFirst()
    }
}
