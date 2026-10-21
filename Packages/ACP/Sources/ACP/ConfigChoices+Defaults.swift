import Foundation

extension ConfigChoices {
    /// Resolves a loaded session: saved choices first, then configured defaults by category, then
    /// whatever the agent reports. Re-evaluate after setting the model, which can change efforts.
    public func fillingDefaults(_ defaults: [String: String], in options: [ConfigOption]) -> ConfigChoices {
        var resolved = self
        var seen: Set<String> = []
        for option in options {
            guard let category = option.category, seen.insert(category).inserted,
                choices[option.id] == nil, let value = defaults[category], !value.isEmpty,
                case .select(_, let values) = option.kind,
                values.contains(where: { $0.value == value })
            else { continue }
            resolved.choose(option, value: value)
        }
        return resolved
    }
}
