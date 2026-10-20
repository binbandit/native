#if NATIVE_AGENT_PICKER_WIP
#if DEBUG
import SwiftUI

/// The built-in agents in every state the picker shows, for its previews; never from a running app.
enum AgentPickerPreviewFixtures {
    static let options: [AgentPickerOption] = [
        option(BuiltInPlugins.codex, .ready, isDefault: true),
        option(
            BuiltInPlugins.claudeCode, .stopped, choice: nil,
            reason: "It exited while starting (status 1): error: unknown option '--acp'", remedy: .restart),
        option(
            BuiltInPlugins.openCode, .needsSignIn, choice: .signInThenStart,
            reason: "Sign in to start sessions with OpenCode, or run `opencode auth login` in a terminal."),
        option(BuiltInPlugins.pi, .starting),
        option(
            BuiltInPlugins.cursor, .notInstalled, choice: nil,
            reason:
                "Native couldn't find `cursor-agent` on your PATH. Install it with `brew install --cask cursor-cli`, then choose Check Again.",
            remedy: .checkAgain),
    ]

    /// The same agents while the project's folder is gone: none can start a session.
    static var blocked: [AgentPickerOption] {
        options.map {
            AgentPickerOption(
                agent: $0.agent, status: $0.status, choice: nil, reason: $0.reason, remedy: $0.remedy,
                isDefault: $0.isDefault)
        }
    }

    private static func option(
        _ plugin: ManifestPlugin,
        _ status: AgentPickerStatus,
        choice: AgentPickerOption.Choice? = .startSession,
        reason: String? = nil,
        remedy: AgentPickerOption.Remedy? = nil,
        isDefault: Bool = false
    ) -> AgentPickerOption {
        let manifest = plugin.manifest
        return AgentPickerOption(
            agent: AgentDefinition(manifest.agents[0], pluginID: manifest.id), status: status, choice: choice,
            reason: reason, remedy: remedy, isDefault: isDefault)
    }
}

#Preview("Agent picker") {
    DSPreviewPair {
        AgentPickerPanel(
            options: AgentPickerPreviewFixtures.options, projectName: "native", missingAgents: ["Copilot"],
            defaultShortcut: "⌘N", onChoose: { _ in }, onRemedy: { _ in }, onAddAgent: {}, onDismiss: {})
    }
}

#Preview("Agent picker, project folder missing") {
    DSPreviewPair {
        AgentPickerPanel(
            options: AgentPickerPreviewFixtures.blocked, projectName: "native", missingAgents: [],
            defaultShortcut: "⌘N", onChoose: { _ in }, onRemedy: { _ in }, onAddAgent: {}, onDismiss: {}
        ) {
            NoticeBanner(
                tone: .warning, title: "Can't find this project's folder",
                detail: "Native looked for it at ~/Developer/native."
            ) {
                Button("Retry") {}.buttonStyle(.ds(.secondary))
            }
            .padding([.horizontal, .top], DS.Space.md)
        }
    }
}
#endif
#endif
