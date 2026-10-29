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
            systemImage: "person.2",
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
    @Environment(\.settingsPlainly) private var plainly
    @Environment(SettingsPresentation.self) private var presentation

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
                description: Text("Agents Native can run tasks with. Each comes from an extension and speaks ACP."),
                plainly: .init(
                    title: "Agents",
                    description: "The coding agents on this Mac. New tasks can start with any agent that's on."))
            SettingsRowGroup {
                ForEach(shownEntries) { entry in
                    agentRow(entry)
                        .settingsLocked(isAllowed(entry) ? nil : Self.notAllowed)
                    if registry.isEnabled(entry.plugin.id), isAllowed(entry) {
                        if !plainly {
                            AgentDefaultsRow(agentName: entry.agent.name, agentID: entry.definition.id)
                                .padding(.leading, SettingsMetrics.iconTile + DS.Space.lg)
                        }
                        NativeToolsSettingsRow(agent: entry.definition, registry: registry)
                            .padding(.leading, SettingsMetrics.iconTile + DS.Space.lg)
                    }
                }
            }
            if plainly {
                Button("New Task Defaults…") { presentation.open(.newTasks) }
                    .buttonStyle(.settings)
                DisclosureGroup("How Native runs agents") {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        ForEach(shownEntries) { entry in
                            VStack(alignment: .leading, spacing: DS.Space.xs) {
                                Text(entry.agent.name).settingsText(.bodyMedium)
                                Text(entry.commandLine)
                                    .settingsText(.mono)
                                    .textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .font(DS.Settings.caption)
                .foregroundStyle(.dsTextSecondary)
            }
            if plainly {
                SettingsSubheading(
                    "Not on this Mac",
                    note: "Install one in Terminal and Native notices. It shows the command; it never runs it for you.")
            } else {
                SettingsHeader(
                    "Add an Agent",
                    description: Text(
                        "Agents Native knows but can't find on this Mac. Install one in your terminal, then check again. Native never runs these commands."
                    ))
            }
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

    static var notAllowed: String { "Not allowed by \(PolicyCenter.organizationName)" }

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
            description: plainly ? Text(status(for: entry)) : Text(entry.commandLine).font(SettingsTextStyle.mono.font),
            detail: plainly ? siblingNote(for: entry) : detail(for: entry)
        ) {
            if !plainly, let runtime, runtime.needsSignIn {
                SettingsBadge("Needs sign-in")
            }
        } control: {
            HStack(spacing: DS.Space.md) {
                if plainly {
                    Button("New Tasks…") { presentation.openNewTasks(agent: entry.definition.id) }
                        .accessibilityLabel("New Tasks for \(entry.agent.name)")
                }
                if let runtime {
                    AgentRowActions(runtime: runtime)
                }
                SettingsSwitch(
                    entry.agent.name,
                    isOn: Binding(
                        get: { registry.isEnabled(entry.plugin.id) && isAllowed(entry) },
                        set: { registry.setEnabled($0, for: entry.plugin.id) }
                    ))
            }
        }
    }

    private func status(for entry: Entry) -> String {
        guard isAllowed(entry) else { return Self.notAllowed }
        guard registry.isEnabled(entry.plugin.id) else { return "Off" }
        guard let runtime = model.runtime(entry.definition.id) else { return "Ready" }
        if runtime.needsSignIn { return "Needs you to sign in" }
        switch runtime.status {
        case .idle, .ready: return "Ready"
        case .starting: return "Starting…"
        case .notInstalled: return "Not installed"
        case .failed: return "Couldn't start"
        }
    }

    private func siblingNote(for entry: Entry) -> Text? {
        let siblings = entry.plugin.agents.filter { $0.id != entry.agent.id }.map(\.name)
        guard !siblings.isEmpty else { return nil }
        return Text(
            "Turning off \(entry.agent.name) also turns off \(ListFormatter.localizedString(byJoining: siblings)).")
    }

    private func detail(for entry: Entry) -> Text {
        var lines = [
            isAllowed(entry)
                ? "When off, Native stops \(entry.agent.name) and doesn't offer it for new tasks."
                : "\(PolicyCenter.organizationSubject) doesn't allow \(entry.agent.name), so Native doesn't start it or offer it for new tasks."
        ]
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

#if DEBUG
#Preview("Agents settings") {
    let app = AppModel.preview()
    DSPreviewPair {
        AgentsSettingsPage(registry: app.plugins)
            .settingsPreviewPage()
    }
    .environment(app)
    .environment(PolicyCenter.shared)
    .environment(SettingsPresentation())
}

#Preview("Plainly - Agents and launch details") {
    let app = AppModel.preview()
    DSPreviewPair {
        AgentsSettingsPage(registry: app.plugins).settingsPreviewPage()
    }
    .environment(app)
    .environment(PolicyCenter.shared)
    .environment(SettingsPresentation())
    .environment(\.settingsPlainly, true)
}
#endif
