import Foundation

/// The config options a client changed on a session (model, mode, effort and the like), so it can
/// set them again when the session is reopened: agents replay a loaded session's transcript, but
/// some reopen it on their defaults (codex-acp 2.2.2 comes back on its default model and mode).
///
/// Only options the client changed are kept. From then on each follows the session, including
/// changes the agent makes itself (leaving Plan Mode, say), so restoring brings the session back to
/// where it was and never undoes the agent.
public struct ConfigChoices: Codable, Hashable, Sendable {
    public struct Choice: Codable, Hashable, Sendable {
        public var value: String
        /// What the option and the value were called, for saying what's gone once the agent stops
        /// offering them.
        public var optionName: String
        public var valueName: String
    }

    /// What reopening does about one choice.
    public enum Restoration: Hashable, Sendable {
        /// Set the option back to the chosen value.
        case set(ConfigOption, value: String)
        /// The agent no longer offers the option or the value, so the session keeps the agent's
        /// value (named `kept`, if the option is still there).
        case unavailable(Choice, kept: String?)
        /// The value isn't allowed anymore (an organization's policy), so the session keeps the
        /// agent's value.
        case forbidden(Choice)
    }

    /// By option id, the id `session/set_config_option` takes.
    public private(set) var choices: [String: Choice] = [:]

    public init() {}

    public var isEmpty: Bool {
        choices.isEmpty
    }

    /// Records that the client set `option` to `value`.
    public mutating func choose(_ option: ConfigOption, value: String) {
        guard case .select(_, let values) = option.kind else { return }
        let name = values.first { $0.value == value }?.name ?? value
        choices[option.id] = Choice(value: value, optionName: option.name, valueName: name)
    }

    /// Moves the chosen options to the values `options` (the session's, now) report. Options the
    /// client never changed stay unrecorded, and ones the session doesn't list stay as they were.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func follow(_ options: [ConfigOption]) -> Bool {
        var changed = false
        for option in options {
            guard let choice = choices[option.id], case .select(let current, _) = option.kind, current != choice.value
            else { continue }
            choose(option, value: current)
            changed = true
        }
        return changed
    }

    public mutating func forget(_ id: String) {
        choices[id] = nil
    }

    /// The order to restore the choices in: the model first, since changing it can change what the
    /// other options offer (a model's efforts), then the rest as the agent lists them, then the
    /// options it no longer lists. None when the agent lists no options at all: it hasn't said what
    /// it offers, so nothing can be compared or called gone.
    public func restoreOrder(in options: [ConfigOption]) -> [String] {
        guard !options.isEmpty else { return [] }
        let listed = options.filter { choices[$0.id] != nil }
        let models = listed.filter { $0.category == "model" }
        let others = listed.filter { $0.category != "model" }
        let missing = choices.keys.filter { id in !options.contains { $0.id == id } }.sorted()
        return (models + others).map(\.id) + missing
    }

    /// `options` as restoring will leave them: each chosen value the option offers and `allows`
    /// permits, in place of the agent's. For showing a reopening session as it's about to be, so
    /// the agent's defaults don't show first.
    public func preview(_ options: [ConfigOption], allows: (ConfigOption, String) -> Bool) -> [ConfigOption] {
        guard !choices.isEmpty else { return options }
        return options.map { option in
            guard let choice = choices[option.id], case .select(let current, let values) = option.kind,
                current != choice.value, values.contains(where: { $0.value == choice.value }),
                allows(option, choice.value)
            else { return option }
            var shown = option
            shown.kind = .select(currentValue: choice.value, options: values)
            return shown
        }
    }

    /// What to do about the choice for option `id` in a reopened session whose options are
    /// `options`: nothing (nil) when the agent restored it itself or nothing was chosen. `allows`
    /// says whether a value is still permitted.
    public func restoration(
        of id: String, in options: [ConfigOption], allows: (ConfigOption, String) -> Bool
    ) -> Restoration? {
        guard let choice = choices[id] else { return nil }
        guard let option = options.first(where: { $0.id == id }), case .select(let current, let values) = option.kind
        else { return .unavailable(choice, kept: nil) }
        guard current != choice.value else { return nil }
        guard values.contains(where: { $0.value == choice.value }) else {
            return .unavailable(choice, kept: values.first { $0.value == current }?.name ?? current)
        }
        guard allows(option, choice.value) else { return .forbidden(choice) }
        return .set(option, value: choice.value)
    }
}
