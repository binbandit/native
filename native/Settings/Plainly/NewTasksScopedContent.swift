import ACP
import Modes
import NativePolicy
import SwiftUI

struct NewTasksScopedContent: View {
    let entry: AgentsSettingsPage.Entry
    let project: Project?
    let registry: PluginRegistry
    let modeLibrary: ModeLibrary
    /// Shows the modes editor, when the page has one.
    var editModes: (() -> Void)?
    @State private var defaults: NewTasksDefaultsModel
    @State private var inventory: NewTasksLoadsModel
    /// The groups' width, for narrowing every row by one rule.
    @State private var width = DS.Settings.pageWidth
    @Environment(AppModel.self) private var app
    @Environment(SettingsPresentation.self) private var presentation

    init(
        entry: AgentsSettingsPage.Entry, project: Project?, registry: PluginRegistry, modeLibrary: ModeLibrary,
        editModes: (() -> Void)? = nil
    ) {
        self.editModes = editModes
        self.entry = entry
        self.project = project
        self.registry = registry
        self.modeLibrary = modeLibrary
        #if DEBUG
        if let state = NewTasksPreviewFixtures.requested {
            _defaults = State(
                initialValue: NewTasksPreviewFixtures.model(
                    agent: entry.definition.id, name: entry.agent.name, project: project, state: state))
        } else {
            _defaults = State(
                initialValue: NewTasksDefaultsModel(
                    agent: entry.definition.id, agentName: entry.agent.name, project: project))
        }
        #else
        _defaults = State(
            initialValue: NewTasksDefaultsModel(
                agent: entry.definition.id, agentName: entry.agent.name, project: project))
        #endif
        _inventory = State(initialValue: NewTasksLoadsModel(agent: entry.agent, project: project, registry: registry))
    }

    var body: some View {
        SettingsGroup(title: "Agent", footer: footer) {
            if let project { NewTasksProjectAgentRow(project: project) }
            NewTasksValueRow(model: defaults, setting: .model, mode: startingMode)
            if !defaults.choices(.effort).isEmpty {
                NewTasksValueRow(model: defaults, setting: .effort, mode: startingMode)
            }
            NewTasksModeRow(library: modeLibrary, project: project)
        } footerAccessory: {
            if let editModes { NewTasksFooterLink(title: "Edit modes in Modes", action: editModes) }
        }
        .preference(key: NewTasksOrganizationCount.self, value: organizationDefaults)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .modifier(NewTasksNarrowing(width: width))
        SettingsGroup(
            title: "Workspace",
            footer:
                "A worktree is a separate copy of the project, so tasks running at once never touch each other's files."
        ) {
            NewTasksWorkspaceRow(project: project)
            SettingsRow("Setup scripts") {
                Button("Git ▸ Scripts…") { presentation.open(.scripts) }.buttonStyle(.plain)
            }
        }
        .modifier(NewTasksNarrowing(width: width))
        SettingsGroup(title: "All agents", footer: "Change permissions for one task in the composer.") {
            PermissionDefaultsRow(project: project?.id)
        }
        .modifier(NewTasksNarrowing(width: width))
        NewTasksLoadsSection(inventory: inventory, window: knownWindow, report: knownReport, fixtureItems: fixtureItems)
            .task {
                guard fixtureItems == nil else { return }
                await inventory.readInstructions(shellEnvironment: await app.shellEnvironment())
            }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                defaults.refresh()
            }
    }

    private var startingMode: Modes.Mode { modeLibrary.startingMode(forProjectAt: project?.url) }

    /// Defaults the organization sets: today only permissions can be.
    private var organizationDefaults: Int {
        PolicyCenter.shared.policy.forbiddenPermissionModes.isEmpty ? 0 : 1
    }

    private var footer: String {
        if defaults.choices(.model).isEmpty { return "Start one task with \(entry.agent.name) to see its models." }
        if startingMode.id != .build {
            return
                "\(startingMode.name) applies its own settings after these defaults. Edit Modes shows what it changes."
        }
        return "The composer's agent menu changes these settings for one task."
    }

    private var fixtureItems: [NewTasksLoadItem]? {
        #if DEBUG
        if let state = NewTasksPreviewFixtures.requested {
            return state == "empty"
                ? []
                : NewTasksPreviewFixtures.items(
                    agent: entry.agent.name, project: project?.name,
                    organization: PolicyCenter.shared.policy.organizationName)
        }
        #endif
        return nil
    }

    /// Open tasks like the next one: same agent and model, in the selected project.
    private var similarSessions: [SessionModel] {
        let selected = defaults.receipt(.model, policy: PolicyCenter.shared.policy, mode: startingMode).value
        return Self.sessions(in: app, agent: entry.definition.id, project: project?.id, model: selected)
    }

    private var knownReport: ContextReport? {
        similarSessions.compactMap { BuiltInPlugins.usage.contextReports.report(for: $0.key) }
            .max { $0.capturedAt < $1.capturedAt }
    }

    private var knownWindow: Int? {
        #if DEBUG
        if NewTasksPreviewFixtures.requested != nil { return 200000 }
        #endif
        if let knownReport { return knownReport.windowTokens }
        return similarSessions.lazy.compactMap(\.usage?.size).first
    }

    /// Matched by the project the catalog files a task under, not its folder: a task in a worktree
    /// works outside the project's checkout.
    static func sessions(
        in app: AppModel, agent: AgentDefinition.ID, project: Project.ID?, model: String
    ) -> [SessionModel] {
        guard let project else { return [] }
        return app.sessions.open(of: agent).filter {
            app.catalog.lookup($0.key)?.project == project
                && ComposerSettings($0.configOptions).model?.currentName == model
        }
    }
}

#if DEBUG
#Preview("New Tasks - Scoped content") {
    let app = AppModel.preview()
    if let entry = AgentsSettingsPage.entries(in: app.plugins).first {
        DSPreviewPair {
            SettingsPage {
                NewTasksScopedContent(
                    entry: entry, project: nil, registry: app.plugins,
                    modeLibrary: ModeLibrary(defaults: PreviewUserDefaults()))
            }.settingsPreviewPage()
        }
        .environment(app).environment(SettingsPresentation())
        .environment(GitSettings(defaults: PreviewUserDefaults())).environment(\.settingsPlainly, true)
    }
}
#endif
