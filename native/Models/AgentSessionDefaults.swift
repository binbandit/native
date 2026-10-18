import ACP
import Foundation
import os

/// Settings the user wants every new session of an agent to start with, such as a cheaper model:
/// `agentDefaults.<agent id>.model` and `.effort` in the user defaults, which a launch argument can
/// also set (`-agentDefaults.codex.model gpt-6.1-sol`). Applied before the first prompt; a value
/// the agent doesn't offer is skipped, never fatal.
enum AgentSessionDefaults {
    /// A setting a default can be given, in the order they're applied: the model first, since
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

    /// The choices the agent offered for `setting` the last time one of its sessions said, so
    /// Settings can list them before any session runs.
    static func offeredChoices(for agent: AgentDefinition.ID, setting: Setting, defaults: UserDefaults = .standard) -> [ConfigOption.SelectOption] {
        // Stored with the wire's field names, so ACP's own decoding reads them back.
        defaults.data(forKey: setting.key(for: agent) + ".offered")
            .flatMap { try? JSONDecoder().decode([ConfigOption.SelectOption].self, from: $0) } ?? []
    }

    /// Remembers what a session of `agent` offers, for `offeredChoices`.
    static func remember(_ options: [ConfigOption], for agent: AgentDefinition.ID, defaults: UserDefaults = .standard) {
        for setting in Setting.allCases {
            guard let option = options.first(where: { $0.category == setting.category }),
                  case .select(_, let choices) = option.kind,
                  let data = try? JSONEncoder().encode(choices.map(OfferedChoice.init))
            else { continue }
            defaults.set(data, forKey: setting.key(for: agent) + ".offered")
        }
    }

    static func apply(to session: SessionModel, defaults: UserDefaults = .standard) async {
        for setting in Setting.allCases {
            let category = setting.category
            guard let value = defaults.string(forKey: setting.key(for: session.agent.id)) else { continue }
            guard let option = session.state.configOptions.first(where: { $0.category == category }),
                  case .select(let current, let choices) = option.kind
            else {
                logger.info("\(session.agent.displayName, privacy: .public) has no \(category, privacy: .public) setting for the default \(value, privacy: .public)")
                continue
            }
            guard choices.contains(where: { $0.value == value }) else {
                logger.info("\(session.agent.displayName, privacy: .public) doesn't offer \(value, privacy: .public) for \(option.name, privacy: .public); keeping \(current, privacy: .public)")
                continue
            }
            await session.setConfigOption(option, to: value)
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
