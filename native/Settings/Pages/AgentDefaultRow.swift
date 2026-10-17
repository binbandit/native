import SwiftUI

/// A setting every new task with an agent starts with, stored at `agentDefaults.<agent>.<name>`
/// where `AgentSessionDefaults` applies it.
enum AgentDefaultSetting: String, CaseIterable {
    case model
    case effort

    var title: String {
        switch self {
        case .model: "Default model"
        case .effort: "Default effort"
        }
    }

    func storageKey(agentID: String) -> String {
        "agentDefaults.\(agentID).\(rawValue)"
    }

    func rowID(agentID: String) -> SettingsRowID {
        SettingsRowID("agent.\(agentID).\(rawValue)")
    }

    /// The choices the agent offered for this setting the last time Native saw them.
    func offeredChoices(agentID: String) -> [SettingsSelect<String?>.Option] {
        // Agents report their models and efforts per session; nothing records the last offer yet.
        []
    }
}

/// Picks one agent default, or clears it so the agent picks.
struct AgentDefaultRow: View {
    let agentName: String
    let agentID: String
    let setting: AgentDefaultSetting

    @AppStorage private var value: String?

    init(agentName: String, agentID: String, setting: AgentDefaultSetting) {
        self.agentName = agentName
        self.agentID = agentID
        self.setting = setting
        _value = AppStorage(setting.storageKey(agentID: agentID))
    }

    private var options: [SettingsSelect<String?>.Option] {
        var options = [SettingsSelect<String?>.Option(value: nil, title: "Agent's default")]
        let offered = setting.offeredChoices(agentID: agentID)
        options += offered
        // A value set elsewhere (a launch argument, an older choice) stays visible so it can be cleared.
        if let value, !offered.contains(where: { $0.value == value }) {
            options.append(.init(value: value, title: value))
        }
        return options
    }

    var body: some View {
        SettingsRow(
            id: setting.rowID(agentID: agentID),
            setting.title,
            description: Text(description)
        ) {
            SettingsSelect(
                label: "\(agentName) \(setting.title.lowercased())", selection: $value, options: options, width: 200
            )
            .disabled(options.count == 1)
        }
    }

    private var description: String {
        if options.count == 1 {
            return "Start a task with \(agentName) once to choose from what it offers."
        }
        return value == nil
            ? "New tasks use whatever \(agentName) picks."
            : "New tasks start with this. A value \(agentName) stops offering is skipped."
    }
}
