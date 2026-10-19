import ACP
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
    /// holds each setting, for `lastUsedName`.
    static func remember(_ options: [ConfigOption], for agent: AgentDefinition.ID, defaults: UserDefaults = .standard) {
        for setting in Setting.allCases {
            guard let option = options.first(where: { $0.category == setting.category }),
                case .select(_, let choices) = option.kind,
                let data = try? JSONEncoder().encode(choices.map(OfferedChoice.init))
            else { continue }
            defaults.set(data, forKey: setting.key(for: agent) + ".offered")
            defaults.set(option.id, forKey: setting.key(for: agent) + ".option")
        }
    }

    /// What the user last picked for the agent's model and its variants.
    static func lastUsed(for agent: AgentDefinition.ID, defaults: UserDefaults = .standard) -> ConfigChoices {
        defaults.data(forKey: lastUsedKey(for: agent))
            .flatMap { try? JSONDecoder().decode(ConfigChoices.self, from: $0) } ?? ConfigChoices()
    }

    /// The name of what new sessions start on for `setting` when Settings leaves it to the last
    /// pick, if there's been one.
    static func lastUsedName(
        for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: setting.key(for: agent) + ".option")
            .flatMap { lastUsed(for: agent, defaults: defaults).choices[$0]?.valueName }
    }

    static func updateLastUsed(
        for agent: AgentDefinition.ID, defaults: UserDefaults = .standard, _ change: (inout ConfigChoices) -> Void
    ) {
        var choices = lastUsed(for: agent, defaults: defaults)
        change(&choices)
        guard let data = try? JSONEncoder().encode(choices) else { return }
        defaults.set(data, forKey: lastUsedKey(for: agent))
    }

    /// Starts a new session on what it should: the project's model, then the defaults from
    /// Settings, then the user's last picks. Policy wins over all of them.
    static func apply(to session: SessionModel, project: Project.ID?, defaults: UserDefaults = .standard) async {
        let agent = session.agent.id
        var categories: [String: String] = [:]
        for setting in Setting.allCases {
            categories[setting.category] = explicitValue(for: agent, setting: setting, defaults: defaults)
        }
        if let project, let model = ProjectTaskDefaults.model(for: project, agent: agent, defaults: defaults) {
            categories[Setting.model.category] = model
        }
        let start = NewSessionChoices(defaults: categories, lastUsed: lastUsed(for: agent, defaults: defaults))
        let allows: (ConfigOption, String) -> Bool = { !PolicyPermissionModes.forbids($0, value: $1) }
        for id in start.order(in: session.state.configOptions) {
            // Read again each time: setting the model can change what the rest offer.
            switch start.start(of: id, in: session.state.configOptions, allows: allows) {
            case .set(let option, let value)?:
                await session.setConfigOption(option, to: value)
            case .unavailable(let choice, let kept)?:
                session.addNotice(
                    "\(session.agentName) doesn't offer \(choice.valueName) anymore, so this session uses \(kept ?? "its default").",
                    isError: false)
                // Said once: later sessions start on the agent's model until the user picks another.
                updateLastUsed(for: agent, defaults: defaults) { $0.forget(id) }
            case nil:
                logger.info(
                    "\(session.agentName, privacy: .public) keeps its own \(id, privacy: .public) for a new session")
            }
        }
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
