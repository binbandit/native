import Foundation

extension BuiltInPlugins {
    /// GitHub Copilot CLI, which speaks ACP itself (`copilot --acp`), so it runs the user's own
    /// `copilot` and updates on its own schedule. It signs in with `copilot login`, a
    /// `COPILOT_GITHUB_TOKEN`/`GH_TOKEN`, or an existing GitHub CLI login; its ACP sign-in method is
    /// terminal-only, so `authenticate` can't do it in-process.
    static let copilot = ManifestPlugin(
        manifest: PluginManifest(
            id: "copilot",
            name: "GitHub Copilot",
            description: "GitHub's coding agent, through the Copilot CLI's built-in ACP server.",
            agents: [
                AgentManifest(
                    id: "copilot",
                    name: "Copilot",
                    symbol: "airplane",
                    command: "copilot",
                    args: ["--acp"],
                    icon: AgentIconSource(apps: ["com.github.CopilotForXcode"], registry: "github-copilot-cli"),
                    setup: AgentSetupGuide(
                        install: "brew install --cask copilot-cli",
                        docs: URL(string: "https://docs.github.com/copilot/how-tos/copilot-cli"),
                        signIn: "copilot login"
                    )
                )
            ]
        ))
}
