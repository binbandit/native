import SwiftUI

extension SettingsPane {
    static func newTasks(registry: PluginRegistry, modes: SettingsPane?) -> SettingsPane {
        SettingsPane(
            id: .newTasks, title: "New Tasks", systemImage: "play", group: .tasks, order: 0,
            keywords: ["defaults", "model", "effort", "agent", "workspace", "worktree", "mode"],
            searchEntries: {
                AgentsSettingsPage.entries(in: registry).filter { registry.isEnabled($0.plugin.id) }.flatMap { entry in
                    AgentSessionDefaults.Setting.allCases.map { setting in
                        SettingsSearchEntry(
                            id: AgentDefaultsRow.settingRowID(agentID: entry.definition.id, setting: setting),
                            title: setting == .model ? "Model" : "Effort", description: entry.agent.name,
                            keywords: [entry.agent.name, "default"])
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

/// The first slice gathers existing defaults. Inheritance and context accounting build on this home.
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

    private var agents: [AgentsSettingsPage.Entry] {
        AgentsSettingsPage.entries(in: registry).filter { registry.isEnabled($0.plugin.id) }
    }

    private var agent: AgentsSettingsPage.Entry? {
        agents.first { $0.definition.id == agentID }
            ?? agents.first { $0.definition.id == model.defaultAgent?.id }
            ?? agents.first
    }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "New Tasks", description: Text("What a task starts with. Set it for every project, or for one."))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DS.Space.lg) { scopes }
                VStack(alignment: .leading, spacing: DS.Space.md) { scopes }
            }
            if let projectID, let project = model.projects.project(projectID) {
                ProjectNewTasksSection(project: project, defaultsOnly: true)
                    .id(project.id)
            } else {
                if let agent {
                    SettingsGroup(title: "Agent") {
                        AgentDefaultsRow(agentName: agent.agent.name, agentID: agent.definition.id)
                            .id(agent.definition.id)
                        NewTasksModeRow(library: modeLibrary)
                    }
                } else {
                    EmptyStateView(
                        "No agents are on", systemImage: "person.2",
                        message: "Turn on an agent to choose what its new tasks start with."
                    ) {
                        Button("Open Agents") { presentation.open(.agents) }
                    }
                }
                SettingsGroup(
                    title: "Workspace",
                    footer:
                        "A worktree is a separate copy of the project, so tasks running at once never touch each other's files."
                ) {
                    NewTasksWorkspaceRow()
                }
            }
            if let modes {
                DisclosureGroup("Edit Modes", isExpanded: $showsModes) {
                    modes.makeContent()
                        .environment(\.settingsSectionTitle, "Modes")
                        .settingsRevealTarget(SettingsPageMap.sectionID(.modes))
                }
                .font(DS.Settings.body)
                .tint(.dsTextSecondary)
            }
        }
        .onAppear { takeScope() }
        .onChange(of: presentation.projectScope) { takeScope() }
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

    @ViewBuilder private var scopes: some View {
        HStack(spacing: DS.Space.md) {
            Text("Project").foregroundStyle(.dsTextSecondary)
            SettingsSelect(
                label: "Project", selection: $projectID,
                options: [.init(value: nil, title: "All projects")]
                    + model.projects.all.map { .init(value: $0.id, title: $0.name) },
                width: DS.Settings.scopeWidth, fieldStyle: true)
        }
        if projectID == nil, !agents.isEmpty {
            HStack(spacing: DS.Space.md) {
                Text("Agent").foregroundStyle(.dsTextSecondary)
                SettingsSelect(
                    label: "Agent",
                    selection: Binding(
                        get: { agent?.definition.id }, set: { agentID = $0 }),
                    options: agents.map { .init(value: $0.definition.id, title: $0.agent.name) },
                    width: DS.Settings.scopeWidth, fieldStyle: true)
            }
        }
    }

    private func takeScope() {
        if let url = presentation.takeProjectScope() {
            projectID = model.projects.all.first { $0.url == url }?.id
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
