import Foundation

extension BuiltInPlugins {
    /// OpenCode, which speaks ACP itself (`opencode acp`), so there's no adapter to pin: it runs the
    /// user's own `opencode` with their providers and config. Its free models work signed out;
    /// other providers sign in with `opencode auth login`.
    static let openCode = ManifestPlugin(manifest: PluginManifest(
        id: "opencode",
        name: "OpenCode",
        description: "The open source coding agent, through its built-in ACP server.",
        agents: [AgentManifest(
            id: "opencode",
            name: "OpenCode",
            symbol: "curlybraces",
            command: "opencode",
            args: ["acp"],
            icon: AgentIconSource(apps: ["ai.opencode.desktop"], registry: "opencode"),
            setup: AgentSetupGuide(
                install: "brew install anomalyco/tap/opencode",
                docs: URL(string: "https://opencode.ai/docs"),
                signIn: "opencode auth login"
            )
        )]
    ))
}
