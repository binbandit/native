import ACP
import Foundation
import Modes
import NativePolicy
import Observation
import TaskDefaults

/// The same persisted choices used by SessionLauncher. Merely inspecting another agent or project
/// never changes the default agent or starts an ACP process.
@Observable
final class NewTasksDefaultsModel {
    let agent: AgentDefinition.ID
    let agentName: String
    let project: Project?
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults

    init(agent: AgentDefinition.ID, agentName: String, project: Project?, defaults: UserDefaults = .standard) {
        self.agent = agent
        self.agentName = agentName
        self.project = project
        self.defaults = defaults
    }

    func refresh() { revision += 1 }

    func choices(_ setting: AgentSessionDefaults.Setting) -> [ConfigOption.SelectOption] {
        _ = revision
        return AgentSessionDefaults.offeredChoices(for: agent, setting: setting, defaults: defaults)
    }

    var hasReportedOptions: Bool {
        _ = revision
        return !AgentSessionDefaults.offeredOptions(for: agent, defaults: defaults).isEmpty
    }

    func followTitle(_ setting: AgentSessionDefaults.Setting) -> String {
        switch AgentSessionDefaults.fallback(for: agent, setting: setting, defaults: defaults) {
        case .lastUsed(let name)?: "Last used (\(name))"
        case .agentDefault(let name)?: "Agent default (\(name))"
        case nil: "Agent default"
        }
    }

    private func key(_ setting: AgentSessionDefaults.Setting) -> String {
        project.map { ProjectTaskDefaults.key(for: $0.id, agent: agent, setting: setting) }
            ?? setting.key(for: agent)
    }

    func stored(_ setting: AgentSessionDefaults.Setting) -> String? {
        _ = revision
        return defaults.string(forKey: key(setting)).flatMap { $0.isEmpty ? nil : $0 }
    }

    func set(_ value: String?, for setting: AgentSessionDefaults.Setting, undoManager: UndoManager? = nil) {
        let previous = stored(setting)
        guard previous != value else { return }
        defaults.set(value, forKey: key(setting))
        refresh()
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated { model.set(previous, for: setting, undoManager: undoManager) }
        }
        undoManager?.setActionName("Change \(setting.title)")
    }

    func receipt(
        _ setting: AgentSessionDefaults.Setting, policy: NativePolicy, mode: Mode = .build
    ) -> NewTasksSettingReceipt {
        let offered = choices(setting)
        let own = AgentSessionDefaults.agentValue(for: agent, setting: setting, defaults: defaults)
        let last = AgentSessionDefaults.lastValue(for: agent, setting: setting, defaults: defaults)
        let user = AgentSessionDefaults.explicitValue(for: agent, setting: setting, defaults: defaults)
        let local = project == nil ? nil : stored(setting)
        let resolution = TaskDefaultResolution(
            offered: offered.map(\.value), agent: own, user: user, project: local, lastUsed: last)
        func name(_ value: String?) -> String? {
            value.map { id in offered.first { $0.value == id }?.name ?? id }
        }
        let snapshots = AgentSessionDefaults.offeredOptions(for: agent, defaults: defaults)
        let modeResolution = ModeResolver.resolve(mode, options: snapshots) { option, value in
            option.category != "mode" || !policy.forbids(permissionMode: value)
        }
        let optionID = snapshots.first { $0.category == setting.category }?.id
        let modeValue = mode.id == .build ? nil : modeResolution.changes.first { $0.optionID == optionID }?.value
        var layers: [NewTasksSettingReceipt.Layer] = []
        if let project {
            layers.append(
                .init(
                    name: project.name, symbol: "folder", value: name(local),
                    wins: resolution.source == .project, overridden: local != nil && resolution.source != .project))
        }
        layers.append(
            .init(
                name: "You", symbol: "person",
                value: name(user ?? last).map {
                    user == nil && last != nil ? "Last used (\($0))" : $0
                }, wins: resolution.source == .user || resolution.source == .lastUsed,
                overridden: (user ?? last) != nil && resolution.source != .user && resolution.source != .lastUsed))
        layers.append(.init(name: agentName, symbol: "terminal", value: name(own), wins: resolution.source == .agent))
        if modeValue != nil {
            layers = layers.map { layer in
                var changed = layer
                changed.wins = false
                changed.overridden = layer.value != nil && !layer.isOrganization
                return changed
            }
            layers.insert(
                .init(name: mode.label, symbol: mode.symbol, value: name(modeValue), wins: true),
                at: min(1, layers.count))
        }
        let source: SettingsSourceLabel.Source
        if modeValue != nil {
            source = .mode(mode.name)
        } else {
            source =
                switch resolution.source {
                case .organization: .policy
                case .project: .project(project?.name ?? "Project")
                case .user, .lastUsed: .user
                case .agent: .agent(agentName)
                }
        }
        // Before the agent reports its choices, a saved one can't be checked yet: not "no longer offered".
        let unavailable = resolution.unavailable && !offered.isEmpty
        let unchecked = resolution.unavailable && offered.isEmpty
        // The saved choice can come from this project, All projects, or the last task; say which.
        let unavailableNote: String? = name(resolution.requested).map { saved in
            let from =
                local != nil || project == nil && user != nil
                ? "" : user != nil ? ", set for All projects," : ", used last,"
            return "\(saved)\(from) is no longer offered, so \(agentName) uses its default."
        }
        return NewTasksSettingReceipt(
            title: setting == .model ? "Model" : "Effort",
            context: "for \(agentName)\(project.map { " in \($0.name)" } ?? " in all projects")",
            value: name(modeValue ?? resolution.value) ?? "Not reported yet",
            source: source, layers: layers,
            note: unavailable
                ? "The saved choice is no longer offered. \(agentName) keeps its own default."
                : unchecked
                    ? "\(agentName) hasn't reported its choices yet. The saved choice applies if it's offered."
                    : resolution.restricted
                        ? "Policy excludes the requested choice. Native uses the agent's allowed default, or its first allowed choice."
                        : "Project settings come first, then your default or last choice, then the agent's own default.",
            help: nil,
            reason: resolution.restricted
                ? resolution.value == own ? "allowed default" : "first allowed" : nil,
            isDefault: stored(setting) == nil, unavailable: unavailable,
            unavailableNote: unavailable ? unavailableNote : nil, modeOverrides: modeValue != nil)
    }
}
