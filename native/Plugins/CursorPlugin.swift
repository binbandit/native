import Foundation

extension BuiltInPlugins {
    /// Cursor's CLI agent, which speaks ACP itself (`cursor-agent acp`), so there's no adapter to
    /// pin: it runs whatever `cursor-agent` the user installed, and that CLI updates itself. Sign-in
    /// is the agent's `cursor_login` method, an existing `cursor-agent login`, or `CURSOR_API_KEY`.
    ///
    /// The CLI also installs itself as `agent`, a name other CLIs (Grok's, for one) claim too, so
    /// it's only ever launched as `cursor-agent`.
    static let cursor = ManifestPlugin(
        manifest: PluginManifest(
            id: "cursor",
            name: "Cursor",
            description: "Cursor's coding agent, through the Cursor CLI's built-in ACP server.",
            agents: [
                AgentManifest(
                    id: "cursor",
                    name: "Cursor",
                    symbol: "cursorarrow",
                    command: "cursor-agent",
                    args: ["acp"],
                    mcpConfig: "cursor",
                    icon: AgentIconSource(apps: ["com.todesktop.230313mzl4w4u92"], registry: "cursor"),
                    setup: AgentSetupGuide(
                        install: "brew install --cask cursor-cli",
                        docs: URL(string: "https://cursor.com/docs/cli/installation")
                    )
                )
            ]
        ))
}
