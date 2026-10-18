import ACP

/// Keeps sessions out of permission modes the organization forbids.
enum PolicyPermissionModes {
    /// The ACP config option category agents use for their permission mode.
    static let category = "mode"

    static func forbids(_ option: ConfigOption, value: String) -> Bool {
        option.category == category && PolicyCenter.shared.policy.forbids(permissionMode: value)
    }

    /// Moves a session that starts in a forbidden mode (an agent's own default, say) to the first
    /// allowed one.
    static func enforce(on session: SessionModel) async {
        guard let option = session.state.configOptions.first(where: { $0.category == category }),
            case .select(let current, let choices) = option.kind,
            PolicyCenter.shared.policy.forbids(permissionMode: current),
            let allowed = choices.first(where: { !PolicyCenter.shared.policy.forbids(permissionMode: $0.value) })
        else { return }
        await session.setConfigOption(option, to: allowed.value)
    }
}
