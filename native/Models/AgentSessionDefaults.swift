import ACP
import Foundation
import os

/// Settings the user wants every new session of an agent to start with, such as a cheaper model:
/// `agentDefaults.<agent id>.model` and `.effort` in the user defaults, which a launch argument can
/// also set (`-agentDefaults.codex.model gpt-6.1-sol`). Applied before the first prompt; a value
/// the agent doesn't offer is skipped, never fatal.
enum AgentSessionDefaults {
    private static let logger = Logger(subsystem: "Native", category: "AgentDefaults")

    /// The config option category each default sets, in the order they're applied: the model first,
    /// since changing it can change the efforts on offer.
    private static let settings = [("model", "model"), ("effort", "thought_level")]

    static func apply(to session: SessionModel, defaults: UserDefaults = .standard) async {
        for (name, category) in settings {
            guard let value = defaults.string(forKey: "agentDefaults.\(session.agent.id.rawValue).\(name)") else { continue }
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
    }
}
