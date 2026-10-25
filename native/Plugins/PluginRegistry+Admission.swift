import AppAppearance
import CodeThemes
import Experiments
import NativePolicy

extension PluginRegistry {
    /// The organization's decision for a loaded plugin, before it contributes, prepares or hears an
    /// event. Built-ins and manifests from disk answer to the same rule in restricted mode.
    func admission(of loaded: LoadedPlugin) -> PluginAdmission {
        policyCenter.policy.admission(
            ofPlugin: loaded.id, origin: loaded.source == .builtIn ? .builtIn : .installed,
            capabilities: loaded.plugin.capabilities)
    }
}

extension PluginManifest {
    /// What the manifest's contributions do, so a plugin that is only data declares itself and a
    /// built-in manifest gets the same decision as the same manifest installed from disk.
    var capabilities: Set<PolicyCapability> {
        var capabilities: Set<PolicyCapability> = []
        if !agents.isEmpty { capabilities.insert(.agentExecution) }
        if agents.contains(where: { $0.icon?.registry != nil }) { capabilities.insert(.iconDownload) }
        if !mcpServers.isEmpty { capabilities.insert(.mcpExecution) }
        if !workflows.isEmpty { capabilities.insert(.automation) }
        if !themes.isEmpty || !iconSets.isEmpty { capabilities.insert(.pluginAppearance) }
        if !celebrations.isEmpty { capabilities.insert(.celebrations) }
        if !experiments.declared.isEmpty { capabilities.insert(.labs) }
        if commandKnowledge != nil { capabilities.insert(.commandKnowledge) }
        return capabilities
    }
}
