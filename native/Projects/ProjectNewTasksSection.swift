import ACP
import SwiftUI

/// How a project's new tasks start: the agent and model, and the worktree or branch they get with
/// its prefix. Each picker's Default follows the setting for every project, and says what that is.
struct ProjectNewTasksSection: View {
    let project: Project
    var defaultsOnly = false
    var prefixOnly = false
    @Environment(\.settingsPlainly) private var plainly

    @Environment(AppModel.self) private var model
    @Environment(GitSettings.self) private var git
    @AppStorage private var agentID: String?

    init(project: Project, defaultsOnly: Bool = false, prefixOnly: Bool = false) {
        self.defaultsOnly = defaultsOnly
        self.prefixOnly = prefixOnly
        self.project = project
        _agentID = AppStorage(ProjectTaskDefaults.agentKey(for: project.id))
    }

    private var rows: ProjectSettingsRows { ProjectSettingsRows(project: project.id) }
    private var overrides: GitSettings.ProjectOverrides { git.overrides(forProjectAt: project.url) }
    private var agent: AgentRuntime? { agentID.flatMap { model.runtime(AgentDefinition.ID(rawValue: $0)) } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                prefixOnly ? "Git" : "New tasks",
                note: prefixOnly ? nil : "How tasks you start in \(project.name) begin, unless you choose otherwise.")
            SettingsRowGroup {
                if !prefixOnly {
                    SettingsRow(id: rows.agent, "Agent", description: Text(agentDescription)) {
                        SettingsSelect(
                            label: "Agent for new tasks", selection: $agentID, options: agentOptions,
                            width: Self.selectWidth)
                    }
                    if let modelAgent {
                        // Its own view, since where the model is kept depends on the agent.
                        ProjectModelDefaultRow(
                            project: project, agent: modelAgent, rowID: rows.model, width: Self.selectWidth
                        )
                        .id(modelAgent.id)
                    } else {
                        SettingsRow(
                            id: rows.model, "Model",
                            description: Text("Choose an installed agent above to pick its model.")
                        ) {
                            SettingsSelect(
                                label: "Model for new tasks", selection: .constant(String?.none),
                                options: [.init(value: nil, title: "Default")], width: Self.selectWidth
                            )
                            .disabled(true)
                        }
                    }
                    SettingsRow(
                        id: rows.workspace, "New tasks get", plainly: .workspace,
                        description: Text("A worktree keeps parallel tasks from editing the same files.")
                    ) {
                        SettingsSelect(
                            label: "New tasks get", selection: override(\.newTaskWorkspace),
                            options: [.init(value: nil, title: "Default (\(git.newTaskWorkspace.title))")]
                                + GitSettings.NewTaskWorkspace.allCases.map { .init(value: $0, title: $0.title) },
                            width: Self.selectWidth)
                    }
                }
                if !defaultsOnly {
                    SettingsRow(
                        id: rows.prefix, "Branch prefix",
                        description: Text(
                            "New branches start with it, like \(git.branchPrefix(forProjectAt: project.url, gitHubLogin: "you"))fix-login-bug."
                        )
                    ) {
                        HStack(spacing: DS.Space.sm) {
                            if overrides.branchPrefixMode == .custom {
                                TextField("prefix", text: customPrefix)
                                    .settingsField()
                                    .frame(width: GitMetrics.prefixFieldWidth)
                            }
                            SettingsSelect(
                                label: "Branch prefix", selection: override(\.branchPrefixMode),
                                options: [.init(value: nil, title: "Default (\(git.branchPrefixMode.title))")]
                                    + GitSettings.BranchPrefixMode.allCases.map { .init(value: $0, title: $0.title) },
                                width: Self.selectWidth)
                        }
                    }
                }
            }
        }
    }

    private static let selectWidth = SettingsMetrics.selectWidth + DS.Space.xxxl * 2

    // MARK: - Agent and model

    /// The agent whose model the project picks: its own, or while it leaves that open, the one
    /// used last.
    private var modelAgent: AgentDefinition? {
        agentID == nil ? model.defaultAgent : agent?.agent
    }

    private var agentOptions: [SettingsSelect<String?>.Option] {
        let lastUsed = model.defaultAgent.map { "Last used (\($0.displayName))" } ?? "Last used"
        var options = [SettingsSelect<String?>.Option(value: nil, title: lastUsed)]
        options += model.agents.map { .init(value: $0.agent.id.rawValue, title: $0.agent.displayName) }
        // An agent that's gone stays visible, so it can be changed.
        if let agentID, agent == nil {
            options.append(.init(value: agentID, title: "\(agentID) (not installed)"))
        }
        return options
    }

    private var agentDescription: String {
        guard let agentID else { return "New tasks start with the agent you used last, unless you pick one." }
        guard let agent, agent.isAvailable else {
            return
                "\(agent?.agent.displayName ?? agentID) can't start tasks right now, so new tasks start with the agent you used last."
        }
        return "New tasks start with \(agent.agent.displayName), unless you pick another."
    }

    // MARK: - Git overrides

    private func override<Value>(_ field: WritableKeyPath<GitSettings.ProjectOverrides, Value?>) -> Binding<Value?> {
        Binding(
            get: { overrides[keyPath: field] },
            set: { value in
                var changed = overrides
                changed[keyPath: field] = value
                git.setOverrides(changed, forProjectAt: project.url)
            })
    }

    private var customPrefix: Binding<String> {
        Binding(
            get: { overrides.customBranchPrefix ?? "" },
            set: { override(\.customBranchPrefix).wrappedValue = $0 })
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Project new tasks") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let project = app.previewProject() {
            ProjectNewTasksSection(project: project)
                .settingsPreviewPage()
        }
    }
    .sidebarPreviewEnvironment(app)
    .environment(GitSettings(defaults: PreviewUserDefaults()))
}
#endif
