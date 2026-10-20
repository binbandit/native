import Foundation

/// What a new session starts on, option by option: the value given for the option's category (a
/// project's model, the user's default in Settings), else what the user last picked for the agent
/// in any session (`lastUsed`), else the agent's own.
///
/// Only the model and its variants (effort, Fast mode and the like) carry over to new sessions:
/// autonomy and Plan Mode belong to the task they were chosen in.
public struct NewSessionChoices: Sendable {
    /// What the start does about one option.
    public enum Start: Hashable, Sendable {
        /// Set the option to the value.
        case set(ConfigOption, value: String)
        /// The model the user last picked isn't offered anymore, so the session keeps the agent's
        /// (named `kept`).
        case unavailable(ConfigChoices.Choice, kept: String?)
    }

    /// Values by option category (`model`, `thought_level`), for the first option of that category.
    public var defaults: [String: String]
    /// What the user last picked for the agent, by option id.
    public var lastUsed: ConfigChoices

    public init(defaults: [String: String] = [:], lastUsed: ConfigChoices = ConfigChoices()) {
        self.defaults = defaults
        self.lastUsed = lastUsed
    }

    /// The option categories a pick carries over to new sessions.
    private static let rememberedCategories: Set<String> = ["model", "thought_level", "model_config"]

    /// Whether picking a value for `option` makes it what the agent's new sessions start on.
    public static func remembers(_ option: ConfigOption) -> Bool {
        option.category.map(rememberedCategories.contains) ?? false
    }

    /// Whether the user picking `value` from `shown` (the option as the composer showed it) is one
    /// to start new sessions on: the model or one of its variants, picked while the session was
    /// `settled` from what the agent said then (`agentHad`), and taken by the agent (`agentHas`). A
    /// pick from anything else says nothing about where new sessions should start: a session still
    /// getting its settings back shows those it's about to get, and an empty or outdated list
    /// isn't the agent's.
    public static func remembersPick(
        _ value: String, from shown: ConfigOption, agentHad: ConfigOption?, agentHas: ConfigOption?, settled: Bool
    ) -> Bool {
        guard settled, remembers(shown), agentHad == shown, case .select(let current, _)? = agentHas?.kind else {
            return false
        }
        return current == value
    }

    /// The options to set, in order: the model first, since changing it can change what the others
    /// offer (a model's efforts), then the rest as the agent lists them.
    public func order(in options: [ConfigOption]) -> [String] {
        let changes = options.filter { option in
            guard let value = wanted(for: option, in: options)?.value, case .select(let current, _) = option.kind
            else { return false }
            return value != current
        }
        let models = changes.filter { $0.category == "model" }
        return (models + changes.filter { $0.category != "model" }).map(\.id)
    }

    /// What to do about option `id` of a session whose options are `options` now: nothing (nil)
    /// when nothing is wanted for it, it's already on that, or the value isn't offered or allowed.
    /// Only a last-picked model that's gone is worth saying: efforts and variants differ by model,
    /// and a default from Settings shows there as one the agent doesn't offer.
    public func start(
        of id: String, in options: [ConfigOption], allows: (ConfigOption, String) -> Bool
    ) -> Start? {
        guard let option = options.first(where: { $0.id == id }), case .select(let current, let values) = option.kind,
            let wanted = wanted(for: option, in: options), wanted.value != current
        else { return nil }
        guard values.contains(where: { $0.value == wanted.value }) else {
            guard let choice = wanted.lastPick, option.category == "model" else { return nil }
            return .unavailable(choice, kept: values.first { $0.value == current }?.name ?? current)
        }
        guard allows(option, wanted.value) else { return nil }
        return .set(option, value: wanted.value)
    }

    /// The value wanted for `option`, and the pick it came from when that's the last one.
    private func wanted(
        for option: ConfigOption, in options: [ConfigOption]
    ) -> (value: String, lastPick: ConfigChoices.Choice?)? {
        if let category = option.category, let value = defaults[category],
            options.first(where: { $0.category == category })?.id == option.id
        {
            return (value, nil)
        }
        guard Self.remembers(option), let choice = lastUsed.choices[option.id] else { return nil }
        return (choice.value, choice)
    }
}
