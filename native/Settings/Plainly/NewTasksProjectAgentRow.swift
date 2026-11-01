import SwiftUI

struct NewTasksProjectAgentRow: View {
    let project: Project
    @Environment(AppModel.self) private var app
    @Environment(\.undoManager) private var undoManager
    @AppStorage private var stored: String?
    @State private var showsSource = false

    init(project: Project) {
        self.project = project
        _stored = AppStorage(ProjectTaskDefaults.agentKey(for: project.id))
    }

    private var options: [SettingsSelect<String?>.Option] {
        var values =
            [
                SettingsSelect<String?>.Option(
                    value: nil, title: "Last used (\(app.defaultAgent?.displayName ?? "agent"))")
            ]
            + app.agents.map { .init(value: $0.agent.id.rawValue, title: $0.agent.displayName) }
        if let stored, !values.contains(where: { $0.value == stored }) {
            values.append(.init(value: stored, title: "\(stored) (unavailable)"))
        }
        return values
    }

    private var receipt: NewTasksSettingReceipt {
        let chosen = stored.flatMap { app.runtime(.init(rawValue: $0)) }
        let wins = chosen?.isAvailable == true
        return NewTasksSettingReceipt(
            title: "Start with", context: "in \(project.name)",
            value: app.defaultAgent(in: project)?.displayName ?? "No agent available",
            source: wins ? .project(project.name) : .user,
            layers: [
                .init(
                    name: project.name, symbol: "folder", value: chosen?.agent.displayName ?? stored, wins: wins,
                    overridden: stored != nil && !wins),
                .init(
                    name: "You", symbol: "person", value: app.defaultAgent.map { "Last used (\($0.displayName))" },
                    wins: !wins),
            ],
            note:
                "An unavailable project agent falls back to the agent used last. The Agent scope above only changes which agent's settings you inspect."
        )
    }

    var body: some View {
        SettingsRow("Start with") {
            NewTasksSourceControl(receipt: receipt, showsSource: $showsSource) {
                NewTasksValueMenu(
                    label: "Agent for new tasks",
                    selection: Binding(
                        get: { stored },
                        set: { value in
                            ProjectTaskDefaults.setAgent(
                                value.map(AgentDefinition.ID.init(rawValue:)), for: project.id, undoManager: undoManager
                            )
                        }),
                    options: options, isDefault: stored == nil
                )
            }
            .contextMenu {
                Button("Why This Value…") { showsSource = true }
                Button("Reset") {
                    ProjectTaskDefaults.setAgent(nil, for: project.id, undoManager: undoManager)
                }
            }
        }
    }
}

#if DEBUG
#Preview("New Tasks - Project agent") {
    let app = AppModel.preview()
    if let project = app.previewProject() {
        DSPreviewPair {
            SettingsRowGroup { NewTasksProjectAgentRow(project: project) }.settingsPreviewPage()
        }.environment(app).environment(\.settingsPlainly, true).defaultAppStorage(PreviewUserDefaults())
    }
}
#endif
