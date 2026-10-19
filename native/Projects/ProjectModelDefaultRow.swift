import ACP
import SwiftUI

/// The model a project's new tasks with one agent start on. Its Default is what that agent's new
/// tasks start on everywhere else: the default from Settings ▸ Agents, or the model picked last.
struct ProjectModelDefaultRow: View {
    let project: Project
    let agent: AgentDefinition
    let rowID: SettingsRowID
    let width: CGFloat

    @AppStorage private var value: String?

    init(project: Project, agent: AgentDefinition, rowID: SettingsRowID, width: CGFloat) {
        self.project = project
        self.agent = agent
        self.rowID = rowID
        self.width = width
        _value = AppStorage(ProjectTaskDefaults.modelKey(for: project.id, agent: agent.id))
    }

    var body: some View {
        SettingsRow(id: rowID, "Model", description: Text(description)) {
            SettingsSelect(label: "Model for new tasks", selection: $value, options: options, width: width)
                .disabled(options.count == 1)
        }
    }

    private var offered: [ConfigOption.SelectOption] {
        AgentSessionDefaults.offeredChoices(for: agent.id, setting: .model)
    }

    private var options: [SettingsSelect<String?>.Option] {
        var options = [SettingsSelect<String?>.Option(value: nil, title: defaultTitle)]
        options += offered.map { .init(value: $0.value, title: $0.name) }
        // A model the agent stopped offering stays visible, so it can be changed.
        if let value, !offered.contains(where: { $0.value == value }) {
            options.append(.init(value: value, title: value))
        }
        return options
    }

    private var defaultTitle: String {
        if let model = AgentSessionDefaults.explicitValue(for: agent.id, setting: .model) {
            return "Default (\(offered.first { $0.value == model }?.name ?? model))"
        }
        return AgentSessionDefaults.lastUsedName(for: agent.id, setting: .model).map { "Last used (\($0))" }
            ?? "Last used"
    }

    private var description: String {
        guard !offered.isEmpty else { return "Start a task with \(agent.displayName) once to choose from its models." }
        return
            "For new \(agent.displayName) tasks in \(project.name). Otherwise they start on the model set in Settings ▸ Agents, or the one you picked last."
    }
}
