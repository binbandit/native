import ACP
import Experiments
import Foundation
import os

/// What every new session of an agent starts on. By default that's what the user last picked for
/// the agent's model and its variants, in any task (`lastUsed`, kept by `SessionModel.pick`). A
/// default set in Settings wins over that: `agentDefaults.<agent id>.model` and `.effort` in the
/// user defaults, which a launch argument can also set (`-agentDefaults.codex.model gpt-6.1-sol`).
/// A project's model wins over both (`ProjectTaskDefaults`). Applied before the first prompt; a
/// value the agent doesn't offer is skipped, never fatal.
enum AgentSessionDefaults {
    /// A setting Settings can give a default, in the order they're applied: the model first, since
    /// changing it can change the efforts on offer.
    enum Setting: String, CaseIterable, Sendable {
        case model, effort

        /// The ACP config option category that holds it.
        var category: String {
            switch self {
            case .model: "model"
            case .effort: "thought_level"
            }
        }

        func key(for agent: AgentDefinition.ID) -> String {
            "agentDefaults.\(agent.rawValue).\(rawValue)"
        }
    }

    private static let logger = Logger(subsystem: "Native", category: "AgentDefaults")

    private static func lastUsedKey(for agent: AgentDefinition.ID) -> String {
        "agentDefaults.\(agent.rawValue).lastUsed"
    }

    /// The default set for `setting` in Settings or by a launch argument. Empty counts as unset, as
    /// a launch argument can make it (`-agentDefaults.codex.model ""`).
    static func explicitValue(
        for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: setting.key(for: agent)).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The choices the agent offered for `setting` the last time one of its sessions said, so
    /// Settings can list them before any session runs.
    static func offeredChoices(
        for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard
    ) -> [ConfigOption.SelectOption] {
        // Stored with the wire's field names, so ACP's own decoding reads them back.
        defaults.data(forKey: setting.key(for: agent) + ".offered")
            .flatMap { try? JSONDecoder().decode([ConfigOption.SelectOption].self, from: $0) } ?? []
    }

    /// Remembers what a session of `agent` offers, for `offeredChoices`, and which of its options
    /// holds each setting, for `fallback`. A session that has just started (`isNew`) is also on the
    /// agent's own defaults, which `fallback` names until the user picks something.
    static func remember(
        _ options: [ConfigOption], for agent: AgentDefinition.ID, isNew: Bool = false,
        defaults: UserDefaults = .standard
    ) {
        if let data = try? JSONEncoder().encode(options.compactMap(AgentSavedConfigOption.init)) {
            defaults.set(data, forKey: "agentDefaults.\(agent.rawValue).offeredConfig")
            if isNew { defaults.set(data, forKey: "agentDefaults.\(agent.rawValue).initialConfig") }
        }
        for setting in Setting.allCases {
            guard let option = options.first(where: { $0.category == setting.category }),
                case .select(let current, let choices) = option.kind,
                let data = try? JSONEncoder().encode(choices.map(OfferedChoice.init))
            else {
                // An option removed by the agent must not remain an editable cached choice.
                for suffix in [".offered", ".option", ".agentDefault"] {
                    defaults.removeObject(forKey: setting.key(for: agent) + suffix)
                }
                continue
            }
            defaults.set(data, forKey: setting.key(for: agent) + ".offered")
            defaults.set(option.id, forKey: setting.key(for: agent) + ".option")
            if isNew {
                defaults.set(current, forKey: setting.key(for: agent) + ".agentDefault")
            }
        }
    }

    /// The last options the agent actually reported, for addressing a task before it exists.
    static func offeredOptions(for agent: AgentDefinition.ID, defaults: UserDefaults = .standard) -> [ConfigOption] {
        var options =
            defaults.data(forKey: "agentDefaults.\(agent.rawValue).offeredConfig")
            .flatMap { try? JSONDecoder().decode([ConfigOption].self, from: $0) } ?? []
        let initial =
            defaults.data(forKey: "agentDefaults.\(agent.rawValue).initialConfig")
            .flatMap { try? JSONDecoder().decode([ConfigOption].self, from: $0) } ?? []
        for setting in Setting.allCases where !options.contains(where: { $0.category == setting.category }) {
            let choices = offeredChoices(for: agent, setting: setting, defaults: defaults)
            guard !choices.isEmpty else { continue }
            let key = setting.key(for: agent)
            let current = defaults.string(forKey: key + ".agentDefault") ?? choices[0].value
            let wire: [String: Any] = [
                "id": defaults.string(forKey: key + ".option") ?? setting.rawValue,
                "name": setting.rawValue.capitalized, "category": setting.category,
                "type": "select", "currentValue": current,
                "options": choices.map { ["value": $0.value, "name": $0.name] },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: wire),
                let option = try? JSONDecoder().decode(ConfigOption.self, from: data)
            {
                options.append(option)
            }
        }
        // A previous task's permission choice is never a new task's default.
        options = options.compactMap { option in
            guard option.category == "mode" else { return option }
            guard let original = initial.first(where: { $0.id == option.id }),
                case .select(let value, _) = original.kind, case .select(_, let choices) = option.kind,
                choices.contains(where: { $0.value == value })
            else { return nil }
            var option = option
            option.kind = .select(currentValue: value, options: choices)
            return option
        }
        return options
    }

    /// What new sessions start on for `setting` when nothing pins it (Settings, a project).
    enum Fallback: Equatable {
        /// What the user last picked, by name.
        case lastUsed(String)
        /// The agent's own default, by name, before the user has picked one.
        case agentDefault(String)
    }

    /// Nil until a session of the agent has said what it offers.
    static func fallback(
        for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard
    ) -> Fallback? {
        let key = setting.key(for: agent)
        if let name = defaults.string(forKey: key + ".option")
            .flatMap({ lastUsed(for: agent, defaults: defaults).choices[$0]?.valueName })
        {
            return .lastUsed(name)
        }
        return defaults.string(forKey: key + ".agentDefault").map { value in
            .agentDefault(
                offeredChoices(for: agent, setting: setting, defaults: defaults).first { $0.value == value }?.name
                    ?? value)
        }
    }

    static func agentValue(
        for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: setting.key(for: agent) + ".agentDefault")
    }

    static func lastValue(
        for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard
    ) -> String? {
        guard let id = defaults.string(forKey: setting.key(for: agent) + ".option")
        else { return nil }
        return lastUsed(for: agent, defaults: defaults).choices[id]?.value
    }

    /// What the user last picked for the agent's model and its variants.
    static func lastUsed(for agent: AgentDefinition.ID, defaults: UserDefaults = .standard) -> ConfigChoices {
        defaults.data(forKey: lastUsedKey(for: agent))
            .flatMap { try? JSONDecoder().decode(ConfigChoices.self, from: $0) } ?? ConfigChoices()
    }

    static func updateLastUsed(
        for agent: AgentDefinition.ID, defaults: UserDefaults = .standard, _ change: (inout ConfigChoices) -> Void
    ) {
        var choices = lastUsed(for: agent, defaults: defaults)
        change(&choices)
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: lastUsedKey(for: agent))
    }

    /// Explicit Settings defaults only: reopening a task must not inherit another task's picks
    /// or a project's defaults for new tasks.
    static func configuredValues(
        for agent: AgentDefinition.ID, defaults: UserDefaults = .standard
    ) -> [String: String] {
        var categories: [String: String] = [:]
        for setting in [Setting.model, .effort] {
            categories[setting.category] = explicitValue(for: agent, setting: setting, defaults: defaults)
        }
        return categories
    }

    /// Starts a new session on what it should: the project's model, then the defaults from
    /// Settings, then the user's last picks. Policy wins over all of them.
    static func apply(to session: SessionModel, project: Project.ID?, defaults: UserDefaults = .standard) async {
        let agent = session.agent.id
        var categories = configuredValues(for: agent, defaults: defaults)
        if let project, let model = ProjectTaskDefaults.model(for: project, agent: agent, defaults: defaults) {
            categories[Setting.model.category] = model
        }
        if ExperimentStore.shared.value(of: .settingsPlainly) {
            for setting in [Setting.model, .effort] {
                categories[setting.category] =
                    project.flatMap {
                        ProjectTaskDefaults.value(for: $0, agent: agent, setting: setting, defaults: defaults)
                    } ?? explicitValue(for: agent, setting: setting, defaults: defaults)
            }
        }
        let start = NewSessionChoices(defaults: categories, lastUsed: lastUsed(for: agent, defaults: defaults))
        let allows: (ConfigOption, String) -> Bool = { !PolicyPermissionModes.forbids($0, value: $1) }
        for id in start.order(in: session.state.configOptions).filter({ id in
            session.state.configOptions.first(where: { $0.id == id })?.category != "mode"
        }) {
            // Read again each time: setting the model can change what the rest offer.
            switch start.start(of: id, in: session.state.configOptions, allows: allows) {
            case .set(let option, let value)?:
                await session.setConfigOption(option, to: value)
            case .unavailable(let choice, let kept)?:
                session.addNotice(
                    "\(session.agentName) doesn't offer \(choice.valueName) anymore, so this task uses \(kept ?? "its default").",
                    isError: false)
                // Said once: later sessions start on the agent's model until the user picks another.
                updateLastUsed(for: agent, defaults: defaults) { $0.forget(id) }
            case nil:
                logger.info(
                    "\(session.agentName, privacy: .public) keeps its own \(id, privacy: .public) for a new session")
            }
        }
        await session.applyPermissionDefault(project: project?.uuidString, defaults: defaults)
        await PolicyPermissionModes.enforce(on: session)
    }
}

/// A select choice as stored for `offeredChoices`, with the wire's field names; the ACP type only
/// decodes.
private struct OfferedChoice: Encodable {
    let value: String
    let name: String
    let description: String?

    init(_ option: ConfigOption.SelectOption) {
        value = option.value
        name = option.name
        description = option.description
    }
}
