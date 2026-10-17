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
                AgentsSettingsPage.entries(in: registry).map { entry in
                    SettingsSearchEntry(id: entry.rowID, title: entry.agent.name, description: entry.commandLine, keywords: [entry.agent.id, entry.agent.command])
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
        var rowID: SettingsRowID { SettingsRowID("agent.\(agent.id)") }
        var commandLine: String { ([agent.command] + agent.args).joined(separator: " ") }
    }

    /// The host's registry, passed in so a client of several hosts can show any of them.
    let registry: PluginRegistry

    static func entries(in registry: PluginRegistry) -> [Entry] {
        registry.plugins.flatMap { loaded in
            loaded.plugin.manifest.agents.map { Entry(agent: $0, plugin: loaded.plugin.manifest) }
        }
    }

    var body: some View {
        SettingsPage {
            SettingsHeader("Agents", description: Text("Agents Native can start sessions with. Each comes from a plugin and speaks ACP."))
            SettingsRowGroup {
                ForEach(Self.entries(in: registry)) { entry in
                    SettingsRow(
                        id: entry.rowID,
                        entry.agent.name,
                        icon: entry.agent.symbol ?? "sparkle",
                        description: Text(entry.commandLine).font(SettingsTextStyle.mono.font),
                        detail: detail(for: entry)
                    ) {
                        SettingsSwitch(entry.agent.name, isOn: Binding(
                            get: { registry.isEnabled(entry.plugin.id) },
                            set: { registry.setEnabled($0, for: entry.plugin.id) }
                        ))
                    }
                }
            }
        }
    }

    private func detail(for entry: Entry) -> Text {
        var lines = ["When off, Native stops \(entry.agent.name) and doesn't offer it for new tasks."]
        // The switch is the plugin's, so it also covers the plugin's other agents.
        let siblings = entry.plugin.agents.filter { $0.id != entry.agent.id }.map(\.name)
        if !siblings.isEmpty {
            lines[0] = "Shares a switch with \(ListFormatter.localizedString(byJoining: siblings)), from the \(entry.plugin.name) extension. " + lines[0]
        }
        if !entry.agent.resolveExecutables.isEmpty {
            lines.append("Uses \(entry.agent.resolveExecutables.values.sorted().joined(separator: ", ")) from your PATH")
        }
        return Text(lines.joined(separator: "\n"))
    }
}
