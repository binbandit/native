import ACP
import SwiftUI

extension AgentSessionDefaults.Setting {
    var title: String {
        switch self {
        case .model: "Default model"
        case .effort: "Default effort"
        case .permissions: "Permissions"
        }
    }

    /// The choice that leaves it to the last pick, named after what a new task gets with it: the
    /// last pick, or before there's one, the agent's own default. Shared with a project's Model row.
    func followTitle(for agent: AgentDefinition.ID) -> String {
        switch AgentSessionDefaults.fallback(for: agent, setting: self) {
        case .lastUsed(let name)?: "Last used (\(name))"
        case .agentDefault(let name)?: "Agent default (\(name))"
        case nil: "Agent default"
        }
    }
}

/// The settings new tasks with one agent start with, one picker each.
struct AgentDefaultsRow: View {
    @Environment(\.settingsPlainly) private var plainly
    @Experiment(.composerNext) private var composerNext
    let agentName: String
    let agentID: AgentDefinition.ID

    static func rowID(agentID: AgentDefinition.ID) -> SettingsRowID {
        SettingsRowID("agent.\(agentID.rawValue).defaults")
    }

    static func settingRowID(agentID: AgentDefinition.ID, setting: AgentSessionDefaults.Setting) -> SettingsRowID {
        SettingsRowID("agent.\(agentID.rawValue).\(setting.rawValue)")
    }

    private var hasChoices: Bool {
        [AgentSessionDefaults.Setting.model, .effort].contains {
            !AgentSessionDefaults.offeredChoices(for: agentID, setting: $0).isEmpty
        }
    }

    var body: some View {
        if plainly {
            ForEach([AgentSessionDefaults.Setting.model, .effort], id: \.self) { setting in
                SettingsRow(
                    id: Self.settingRowID(agentID: agentID, setting: setting), setting == .model ? "Model" : "Effort",
                    description: hasChoices || setting != .model
                        ? nil : Text("Start one task with \(agentName) to see its models.")
                ) {
                    VStack(alignment: .trailing, spacing: DS.Space.xs) {
                        AgentDefaultPicker(agentName: agentName, agentID: agentID, setting: setting)
                        if composerNext {
                            AgentDefaultSource(agentName: agentName, agentID: agentID, setting: setting)
                        }
                    }
                }
            }
        } else {
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
                    ForEach([AgentSessionDefaults.Setting.model, .effort], id: \.self) { setting in
                        AgentDefaultPicker(agentName: agentName, agentID: agentID, setting: setting)
                    }
                }
            }
            // The pickers get a line of their own, under the text, so they fit narrow windows and iPad.
            .settingsControlBelow()
        }
    }
}

private struct AgentDefaultSource: View {
    let agentName: String
    let agentID: AgentDefinition.ID
    let setting: AgentSessionDefaults.Setting
    @AppStorage private var stored: String?

    init(agentName: String, agentID: AgentDefinition.ID, setting: AgentSessionDefaults.Setting) {
        self.agentName = agentName
        self.agentID = agentID
        self.setting = setting
        _stored = AppStorage(setting.key(for: agentID))
    }

    var body: some View {
        if stored?.isEmpty == false {
            SettingsSourceLabel(source: .user)
        } else if case .lastUsed = AgentSessionDefaults.fallback(for: agentID, setting: setting) {
            SettingsSourceLabel(source: .user)
        } else {
            SettingsSourceLabel(source: .agent(agentName))
        }
    }
}

/// Picks one default, or leaves it to the last pick.
private struct AgentDefaultPicker: View {
    @Environment(\.settingsPlainly) private var plainly
    let agentName: String
    let agentID: AgentDefinition.ID
    let setting: AgentSessionDefaults.Setting

    @AppStorage private var stored: String?

    init(agentName: String, agentID: AgentDefinition.ID, setting: AgentSessionDefaults.Setting) {
        self.agentName = agentName
        self.agentID = agentID
        self.setting = setting
        _stored = AppStorage(setting.key(for: agentID))
    }

    /// Empty counts as unset, as it does for new sessions (`AgentSessionDefaults.explicitValue`).
    private var value: Binding<String?> {
        Binding(get: { stored.flatMap { $0.isEmpty ? nil : $0 } }, set: { stored = $0 })
    }

    private var options: [SettingsSelect<String?>.Option] {
        let offered = AgentSessionDefaults.offeredChoices(for: agentID, setting: setting).map {
            SettingsSelect<String?>.Option(value: $0.value, title: $0.name)
        }
        var options = [SettingsSelect<String?>.Option(value: nil, title: setting.followTitle(for: agentID))] + offered
        // A value set elsewhere (a launch argument, an older choice) stays visible so it can be cleared.
        if let value = value.wrappedValue, !offered.contains(where: { $0.value == value }) {
            options.append(.init(value: value, title: value))
        }
        return options
    }

    var body: some View {
        SettingsSelect(
            label: "\(agentName) \(setting.title.lowercased())", selection: value, options: options,
            width: SettingsMetrics.selectWidth + DS.Space.xxxl * 2, isDefault: value.wrappedValue == nil
        )
        .disabled(options.count == 1)
        .contextMenu { if plainly { Button("Reset") { stored = nil } } }
    }
}

#if DEBUG
#Preview("Agent defaults row") {
    DSPreviewPair {
        SettingsRowGroup {
            AgentDefaultsRow(agentName: "Claude Code", agentID: AgentDefinition.ID(rawValue: "claude-code"))
            AgentDefaultsRow(agentName: "Codex", agentID: AgentDefinition.ID(rawValue: "codex"))
        }
        .settingsPreviewPage()
    }
}
#endif
