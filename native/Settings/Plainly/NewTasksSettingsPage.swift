import NativePolicy
import SwiftUI

extension SettingsPane {
    static func newTasks(registry: PluginRegistry, modes: SettingsPane?) -> SettingsPane {
        SettingsPane(
            id: .newTasks, title: "New Tasks", systemImage: "play", group: .tasks, order: 0,
            keywords: ["defaults", "model", "effort", "agent", "workspace", "worktree", "mode"],
            searchEntries: {
                AgentsSettingsPage.entries(in: registry).filter {
                    registry.isEnabled($0.plugin.id) && PolicyCenter.shared.policy.agents.allows($0.agent.id)
                }.flatMap { entry in
                    AgentSessionDefaults.Setting.allCases.map { setting in
                        SettingsSearchEntry(
                            id: AgentDefaultsRow.settingRowID(agentID: entry.definition.id, setting: setting),
                            title: setting == .model ? "Model" : setting == .effort ? "Effort" : "Permissions",
                            description: entry.agent.name,
                            keywords: [entry.agent.name, "default"], scopeName: entry.agent.name)
                    }
                } + [
                    SettingsSearchEntry(
                        id: GitSettingsPage.workspaceRow, title: "Work in", keywords: ["branch", "worktree"]),
                    SettingsSearchEntry(id: .modesDefault, title: "Mode", keywords: ["build", "plan", "review"]),
                ] + (modes?.searchEntries().filter { $0.id != .modesDefault } ?? [])
            }
        ) {
            NewTasksSettingsPage(registry: registry, modes: modes)
        }
    }
}

/// One home for the starting point of every agent and project.
struct NewTasksSettingsPage: View {
    let registry: PluginRegistry
    let modes: SettingsPane?
    var modeLibrary = ModeLibrary.shared

    @Environment(AppModel.self) private var model
    @Environment(SettingsPresentation.self) private var presentation
    @Environment(\.settingsFlash) private var flash
    @State private var projectID: Project.ID?
    @State private var agentID: AgentDefinition.ID?
    @State private var showsModes = false
    @State private var organizationCount = 0

    private var agents: [AgentsSettingsPage.Entry] {
        AgentsSettingsPage.entries(in: registry).filter {
            registry.isEnabled($0.plugin.id) && PolicyCenter.shared.policy.agents.allows($0.agent.id)
        }
    }

    private var agent: AgentsSettingsPage.Entry? {
        agents.first { $0.definition.id == agentID }
            ?? agents.first { $0.definition.id == model.defaultAgent(in: selectedProject)?.id }
            ?? agents.first
    }

    private var selectedProject: Project? { projectID.flatMap { model.projects.project($0) } }

    var body: some View {
        SettingsPage {
            SettingsHeader("New Tasks", description: Text(description))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.lg) {
                    scopes
                    Spacer(minLength: DS.Space.md)
                    organizationSets
                }
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    scopes
                    organizationSets
                }
            }
            if let agent {
                NewTasksScopedContent(
                    entry: agent, project: selectedProject, registry: registry, modeLibrary: modeLibrary,
                    editModes: editModes
                )
                .id("\(projectID?.uuidString ?? "all")/\(agent.definition.id.rawValue)")
            } else {
                EmptyStateView(
                    "No agents are on", systemImage: "person.2",
                    message: "Turn on an agent to choose what its new tasks start with."
                ) {
                    Button("Open Agents") { presentation.open(.agents) }
                }
                SettingsGroup(title: "Defaults") {
                    NewTasksModeRow(library: modeLibrary)
                } footerAccessory: {
                    if let editModes { NewTasksFooterLink(title: "Edit modes in Modes", action: editModes) }
                }
                SettingsGroup(title: "Workspace") { NewTasksWorkspaceRow() }
            }
            if let modes, showsModes {
                modes.makeContent()
                    .environment(\.settingsSectionTitle, "Modes")
                    .settingsRevealTarget(SettingsPageMap.sectionID(.modes))
            }
        }
        .onPreferenceChange(NewTasksOrganizationCount.self) { organizationCount = $0 }
        .onAppear { takeScope() }
        .onChange(of: presentation.projectScope) { takeScope() }
        .onChange(of: presentation.agentScope) { takeScope() }
        .task(id: flash) {
            guard let row = flash?.rowID else { return }
            if row == GitSettingsPage.workspaceRow || row == .modesDefault { projectID = nil }
            if let match = agents.first(where: { row.rawValue.hasPrefix("agent.\($0.agent.id).") }) {
                projectID = nil
                agentID = match.definition.id
            }
            if (row.rawValue.hasPrefix("modes.") && row != .modesDefault)
                || row == SettingsPageMap.sectionID(.modes)
            {
                showsModes = true
            }
        }
    }

    /// The organization's name to start a sentence: "Your organization" when it gave none.
    private var organizationName: String {
        let name = PolicyCenter.shared.policy.organizationDisplayName
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private var description: String {
        let scope = selectedProject.map { "What a task in \($0.name) starts with." } ?? "What a task starts with."
        if organizationCount > 0 {
            return
                "\(scope) \(organizationName) sets some of it for every Mac it manages."
        }
        return selectedProject.map {
            "\(scope) Marked values are \($0.name)'s own; the rest follow your settings."
        } ?? "\(scope) Set it for every project, or for one."
    }

    /// Opens the modes editor below and scrolls to it. Nil when the page has no modes to edit.
    private var editModes: (() -> Void)? {
        guard modes != nil else { return nil }
        return { presentation.open(.newTasks, revealing: SettingsPageMap.sectionID(.modes)) }
    }

    /// "Northwind Federal IT sets 4", trailing the scopes, while the organization sets anything here.
    @ViewBuilder private var organizationSets: some View {
        if organizationCount > 0 {
            SettingsSourceLabel(
                source: .organization(
                    "\(organizationName) sets \(organizationCount)"))
        }
    }

    @ViewBuilder private var scopes: some View {
        HStack(spacing: DS.Space.md) {
            Text("Project").foregroundStyle(.dsTextSecondary)
            SettingsSelect(
                label: "Project",
                selection: Binding(
                    get: { projectID },
                    set: {
                        projectID = $0; agentID = nil
                    }),
                options: [.init(value: nil, title: "All projects")]
                    + model.projects.all.map { .init(value: $0.id, title: $0.name) },
                width: DS.Settings.scopeCompactWidth, fieldStyle: true)
        }
        if !agents.isEmpty {
            HStack(spacing: DS.Space.md) {
                Text("Agent").foregroundStyle(.dsTextSecondary)
                SettingsSelect(
                    label: "Agent",
                    selection: Binding(
                        get: { agent?.definition.id }, set: { agentID = $0 }),
                    options: agents.map { .init(value: $0.definition.id, title: $0.agent.name) },
                    width: DS.Settings.scopeCompactWidth, fieldStyle: true)
            }
        }
    }

    private func takeScope() {
        if let requested = presentation.takeAgentScope() { projectID = nil; agentID = requested }
        if let url = presentation.takeProjectScope(for: .newTasks) {
            projectID = model.projects.all.first { $0.url == url }?.id
            agentID = nil
        }
    }
}

#if DEBUG
#Preview("New Tasks - Defaults and empty models") {
    let app = AppModel.preview()
    DSPreviewPair {
        NewTasksSettingsPage(
            registry: app.plugins, modes: nil, modeLibrary: ModeLibrary(defaults: PreviewUserDefaults())
        ).settingsPreviewPage()
    }
    .environment(app)
    .environment(SettingsPresentation())
    .environment(GitSettings(defaults: PreviewUserDefaults()))
    .environment(\.settingsPlainly, true)
    .defaultAppStorage(PreviewUserDefaults())
}

#Preview("New Tasks - No agents") {
    DSPreviewPair {
        NewTasksSettingsPage(
            registry: PluginRegistry(builtIns: [], defaults: PreviewUserDefaults()), modes: nil,
            modeLibrary: ModeLibrary(defaults: PreviewUserDefaults())
        ).settingsPreviewPage(width: 420)
    }
    .environment(AppModel.preview())
    .environment(SettingsPresentation())
    .environment(GitSettings(defaults: PreviewUserDefaults()))
    .environment(\.settingsPlainly, true)
    .defaultAppStorage(PreviewUserDefaults())
}

#Preview("New Tasks - One project") {
    let app = AppModel.preview()
    let presentation = SettingsPresentation()
    if let project = app.previewProject() {
        let _ = presentation.open(.newTasks, scopedTo: project.url)
        DSPreviewPair {
            NewTasksSettingsPage(
                registry: app.plugins, modes: nil, modeLibrary: ModeLibrary(defaults: PreviewUserDefaults())
            ).settingsPreviewPage()
        }
        .environment(app)
        .environment(presentation)
        .environment(GitSettings(defaults: PreviewUserDefaults()))
        .environment(\.settingsPlainly, true)
        .defaultAppStorage(PreviewUserDefaults())
    }
}
#endif
