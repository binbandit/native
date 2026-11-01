import NativeCommands
import Observation

/// Registers the task screen's tools: Native's own, and enabled plugins', kept in step as plugins
/// come and go, each with its command so it can be given a key.
@MainActor
enum SessionToolsWiring {
    /// The plugin tools' commands registered last, so ones whose tool has gone are removed.
    private static var pluginCommands: Set<CommandID> = []

    static func registerBuiltIns(_ registry: SessionToolRegistry, git: GitStore, gitHub: GitHubModel) {
        registry.register(SessionChangesTool.contribution(git: git, gitHub: gitHub))
    }

    /// Hands the registry what enabled plugins add, then watches them again.
    static func connectPlugins(_ registry: SessionToolRegistry, plugins: PluginRegistry, commands: CommandRegistry) {
        // Only the plugins are read while tracking, so updating the registry can't re-trigger it.
        let tools = withObservationTracking {
            plugins.sessionTools
        } onChange: {
            Task { @MainActor in connectPlugins(registry, plugins: plugins, commands: commands) }
        }
        registry.setPluginTools(tools)
        let toolCommands = tools.map { NativeCommand.taskWellTool(TaskWellTool($0)) }
        let ids = Set(toolCommands.map(\.id))
        commands.unregister(pluginCommands.subtracting(ids))
        commands.register(toolCommands)
        pluginCommands = ids
    }
}
