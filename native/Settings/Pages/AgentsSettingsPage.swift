import NativePolicy
import SwiftUI

extension SettingsPane.ID {
    static let agents = Self("agents")
}

extension SettingsPane {
    static func agents(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .agents,
            title: "Agents",
            systemImage: "wifi.router",
            group: .agents,
            order: 0,
            searchEntries: {
                AgentsSettingsPage.entries(in: registry).flatMap { entry in
                    [
                        SettingsSearchEntry(
                            id: entry.rowID, title: entry.agent.name, description: entry.commandLine,
                            keywords: [entry.agent.id, entry.agent.command])
                    ]
                        + [
                            SettingsSearchEntry(
                                id: AgentDefaultsRow.rowID(agentID: entry.definition.id),
                                title: "\(entry.agent.name) defaults",
                                description: "Default model and effort for new tasks",
                                keywords: ["model", "effort", "thinking"])
                        ]
                }
            },
            content: { AgentsSettingsPage(registry: registry) }
        )
    }
}

/// Every agent plugins provide. Disabled plugins' agents stay listed so they can be turned back on
/// here; `registry.agents` only has the enabled ones.
struct AgentsSettingsPage: View {
    struct Entry: Identifiable {
        let agent: AgentManifest
        let plugin: PluginManifest

        var id: String { agent.id }
        var definition: AgentDefinition { AgentDefinition(agent, pluginID: plugin.id) }
        var rowID: SettingsRowID { SettingsRowID("agent.\(agent.id)") }
        var commandLine: String { ([agent.command] + agent.args).joined(separator: " ") }
    }

    /// The host's registry, passed in so a client of several hosts can show any of them.
    let registry: PluginRegistry

    @Environment(AppModel.self) private var model
    @Environment(PolicyCenter.self) private var policy

    static func entries(in registry: PluginRegistry) -> [Entry] {
        registry.plugins.flatMap { loaded in
            loaded.plugin.manifest.agents.map { Entry(agent: $0, plugin: loaded.plugin.manifest) }
        }
    }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Agents",
                description: Text("Agents Native can run tasks with. Each comes from an extension and speaks ACP."))
            SettingsRowGroup {
                ForEach(shownEntries) { entry in
                    agentRow(entry)
                        .settingsLocked(isAllowed(entry) ? nil : Self.notAllowed)
                    if registry.isEnabled(entry.plugin.id), isAllowed(entry) {
                        AgentDefaultsRow(agentName: entry.agent.name, agentID: entry.definition.id)
                            // Under the agent's name, past its icon.
                            .padding(.leading, SettingsMetrics.iconTile + DS.Space.lg)
                    }
                }
            }
            SettingsHeader(
                "Add an Agent",
                description: Text(
                    "Agents Native knows but can't find on this Mac. Install one in your terminal, then check again. Native never runs these commands."
                ))
            AddAgentList(agents: model.agentsToAdd, summaries: registry.descriptions) {
                await model.checkForAgents()
            }
        }
    }

    /// Agents that aren't installed are under Add an Agent instead, unless they're off or the
    /// organization doesn't allow them, which the row explains.
    private var shownEntries: [Entry] {
        Self.entries(in: registry).filter {
            model.installations.isInstalled($0.definition.id) || !registry.isEnabled($0.plugin.id) || !isAllowed($0)
        }
    }

    static let notAllowed = "Not allowed by your organization"

    private func isAllowed(_ entry: Entry) -> Bool {
        policy.policy.agents.allows(entry.agent.id)
    }

    private func agentRow(_ entry: Entry) -> some View {
        HStack(spacing: DS.Space.lg) {
            SettingsIconTile {
                AgentIcon(agent: entry.definition, style: .tile, size: SettingsMetrics.tileGlyph + DS.Space.xs)
            }
            row(entry)
        }
    }

    private func row(_ entry: Entry) -> some View {
        let runtime = model.runtime(entry.definition.id)
        return SettingsRow(
            id: entry.rowID,
            title: Text(entry.agent.name),
            description: Text(entry.commandLine).font(SettingsTextStyle.mono.font),
            detail: detail(for: entry)
        ) {
            if let runtime, runtime.needsSignIn {
                SettingsBadge("Needs sign-in")
            }
        } control: {
            HStack(spacing: DS.Space.md) {
                if let runtime {
                    AgentRowActions(runtime: runtime)
                }
                SettingsSwitch(
                    entry.agent.name,
                    isOn: Binding(
                        get: { registry.isEnabled(entry.plugin.id) },
                        set: { registry.setEnabled($0, for: entry.plugin.id) }
                    ))
            }
        }
    }

    private func detail(for entry: Entry) -> Text {
        var lines = ["When off, Native stops \(entry.agent.name) and doesn't offer it for new tasks."]
        // The switch is the plugin's, so it also covers the plugin's other agents.
        let siblings = entry.plugin.agents.filter { $0.id != entry.agent.id }.map(\.name)
        if !siblings.isEmpty {
            lines[0] =
                "Shares a switch with \(ListFormatter.localizedString(byJoining: siblings)), from the \(entry.plugin.name) extension. "
                + lines[0]
        }
        if !entry.agent.resolveExecutables.isEmpty {
            lines.append(
                "Uses \(entry.agent.resolveExecutables.values.sorted().joined(separator: ", ")) from your PATH")
        }
        return Text(lines.joined(separator: "\n"))
    }
}
