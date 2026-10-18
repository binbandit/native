import ACP
import Foundation

// What a choice costs, said at the point of choice, so the user never learns it from the bill.

extension SelectSetting {
    /// The agent's own pick: its "default" value, or the option it names "(recommended)" (Claude
    /// Code's model list). ACP has no flag for this yet.
    func isRecommended(_ choice: Choice) -> Bool {
        choice.value == Self.defaultValue || choice.name.localizedCaseInsensitiveContains("(recommended)")
    }

    /// A choice's name without the agent's "(recommended)" aside, which the picker shows as a badge.
    func displayName(of choice: Choice) -> String {
        let name = choice.name.replacing(/\s*\(recommended\)\s*$/.ignoresCase(), with: "")
        return name.isEmpty ? choice.name : name
    }

    /// A neutral note on an effort level: the agent's default is recommended, and the top level of
    /// several spends limits faster. Agents don't report relative cost over ACP yet.
    func effortNote(for choice: Choice) -> String? {
        if isRecommended(choice) {
            return "Recommended"
        }
        if levels.count > 1, choice.value == levels.last?.value {
            return "Uses limits faster"
        }
        return nil
    }
}

extension SelectSetting {
    /// A choice's one-line purpose, without the name the agent repeats at its start ("Opus 5.5 ·
    /// Best for everyday, complex tasks"); nil when it says nothing the name doesn't.
    func detail(of choice: Choice) -> String? {
        guard let description = choice.description, description != choice.name else { return nil }
        let prefix = "\(displayName(of: choice)) · "
        return description.hasPrefix(prefix) ? String(description.dropFirst(prefix.count)) : description
    }
}
