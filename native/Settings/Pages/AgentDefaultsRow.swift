import ACP
import SwiftUI

extension AgentSessionDefaults.Setting {
    var title: String {
        switch self {
        case .model: "Default model"
        case .effort: "Default effort"
        }
    }
}

/// The settings new tasks with one agent start with, one picker each.
struct AgentDefaultsRow: View {
    let agentName: String
    let agentID: AgentDefinition.ID

    static func rowID(agentID: AgentDefinition.ID) -> SettingsRowID {
        SettingsRowID("agent.\(agentID.rawValue).defaults")
    }

    private var hasChoices: Bool {
        AgentSessionDefaults.Setting.allCases.contains {
            !AgentSessionDefaults.offeredChoices(for: agentID, setting: $0).isEmpty
        }
    }

    var body: some View {
        SettingsRow(
            id: Self.rowID(agentID: agentID),
            "Defaults for new tasks",
            description: Text(
                hasChoices
                    ? "New tasks start on what you last picked for \(agentName), unless you choose a default here. A value it stops offering is skipped."
                    : "Start a task with \(agentName) once to choose from its models and efforts."
            )
        ) {
            HStack(spacing: DS.Space.md) {
                ForEach(AgentSessionDefaults.Setting.allCases, id: \.self) { setting in
                    AgentDefaultPicker(agentName: agentName, agentID: agentID, setting: setting)
                }
            }
        }
        // The pickers get a line of their own, under the text, so they fit narrow windows and iPad.
        .settingsControlBelow()
    }
}

/// Picks one default, or leaves it to the last pick.
private struct AgentDefaultPicker: View {
    let agentName: String
    let agentID: AgentDefinition.ID
    let setting: AgentSessionDefaults.Setting

    @AppStorage private var value: String?

    init(agentName: String, agentID: AgentDefinition.ID, setting: AgentSessionDefaults.Setting) {
        self.agentName = agentName
        self.agentID = agentID
        self.setting = setting
        _value = AppStorage(setting.key(for: agentID))
    }

    private var options: [SettingsSelect<String?>.Option] {
        let offered = AgentSessionDefaults.offeredChoices(for: agentID, setting: setting).map {
            SettingsSelect<String?>.Option(value: $0.value, title: $0.name)
        }
        let lastUsed = AgentSessionDefaults.lastUsedName(for: agentID, setting: setting).map { "Last used (\($0))" }
        var options = [SettingsSelect<String?>.Option(value: nil, title: lastUsed ?? "Last used \(setting.rawValue)")] + offered
        // A value set elsewhere (a launch argument, an older choice) stays visible so it can be cleared.
        if let value, !offered.contains(where: { $0.value == value }) {
            options.append(.init(value: value, title: value))
        }
        return options
    }

    var body: some View {
        SettingsSelect(
            label: "\(agentName) \(setting.title.lowercased())", selection: $value, options: options,
            width: SettingsMetrics.selectWidth + DS.Space.xxl
        )
        .disabled(options.count == 1)
    }
}
