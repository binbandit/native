import ACP

/// Keeps a pull request question's agent from changing anything, through the agent's own
/// permission mode (the `mode` config option), whichever agent it is: a mode named read-only,
/// else Plan Mode, which only plans, else the least autonomous level the agent lists first.
enum PullRequestAskMode {
    /// The choice to switch to, or nil when the agent has no permission mode.
    static func readOnlyChoice(in options: [ConfigOption]) -> (option: ConfigOption, value: String)? {
        guard let option = options.first(where: { $0.category == PolicyPermissionModes.category }),
            case .select(_, let choices) = option.kind
        else { return nil }
        let allowed = choices.filter { !PolicyPermissionModes.forbids(option, value: $0.value) }
        let readOnly = allowed.first { choice in
            [choice.value, choice.name].contains { name in
                let words = name.lowercased().filter(\.isLetter)
                return words == "readonly"
            }
        }
        let plan = allowed.first { $0.value == ComposerSettings.planValue }
        return (readOnly ?? plan ?? allowed.first).map { (option, $0.value) }
    }

    /// Switches the session to it. Returns whether the session is now in a mode that can't
    /// change anything on its own.
    @discardableResult
    static func apply(to session: SessionModel) async -> Bool {
        guard let (option, value) = readOnlyChoice(in: session.state.configOptions) else { return false }
        await session.setConfigOption(option, to: value)
        return session.state.configOptions.contains { option in
            if option.category == PolicyPermissionModes.category, case .select(let current, _) = option.kind {
                current == value
            } else {
                false
            }
        }
    }
}
