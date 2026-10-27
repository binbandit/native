import NativeHostProtocol
import NativePolicy
import SwiftUI

/// The compatibility switch lives beside the agent's other task defaults.
struct NativeToolsSettingsRow: View {
    let agent: AgentDefinition
    let registry: PluginRegistry
    @Environment(AppModel.self) private var model

    var body: some View {
        SettingsRow(
            id: Self.rowID(agent.id), "Native tools",
            description: Text(
                supportsSkill
                    ? "Uses a skill when available, with MCP as a fallback. Turn on to always load Native's MCP tools."
                    : "This agent uses MCP to access Native's tasks and setup tools."),
            detail: Text(
                "Applies when a task is next opened. Both paths follow the same permissions and organization policy.")
        ) {
            SettingsSwitch(
                "Load Native MCP tools for \(agent.displayName)",
                isOn: Binding(
                    get: { registry.nativeMCPEnabled(for: agent) },
                    set: { model.setNativeMCPEnabled($0, for: agent.id) }))
        }
        .settingsLocked(isAllowed ? nil : "Native tools are not allowed by your organization")
    }

    static func rowID(_ agent: AgentDefinition.ID) -> SettingsRowID {
        SettingsRowID("agent.\(agent.rawValue).nativeTools")
    }

    private var supportsSkill: Bool {
        agent.manifest.nativeSkill == .claudeCode || agent.manifest.nativeSkill == .codex
    }

    private var isAllowed: Bool {
        let policy = registry.policyCenter.policy
        return policy.decision(for: .orchestration).isPermitted
            && policy.decision(for: .mcpExecution).isPermitted && policy.mcp.allows(name: "native")
    }
}

#if DEBUG
#Preview("Native tools - Skill and MCP fallback") {
    let model = AppModel.preview()
    let registry = PluginRegistry(previewing: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex, BuiltInPlugins.cursor])
    registry.setNativeMCPEnabled(true, for: AgentDefinition.ID(rawValue: "codex"))
    return DSPreviewPair {
        SettingsPage {
            SettingsRowGroup {
                ForEach(registry.agents) { agent in
                    NativeToolsSettingsRow(agent: agent, registry: registry)
                }
            }
        }
        .settingsPreviewPage()
    }
    .environment(model)
}
#endif
