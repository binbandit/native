import ACP
import NativePolicy

/// Checks both Native's shared choice and the actual provider control. Legacy policy IDs continue
/// to cap their equivalent Native mode after migration.
enum PolicyPermissionModes {
    static let category = "mode"

    static func forbids(_ option: ConfigOption, value: String) -> Bool {
        forbids(option, value: value, forbidden: PolicyCenter.shared.policy.forbiddenPermissionModes)
    }

    static func forbids(_ option: ConfigOption, value: String, forbidden: Set<String>) -> Bool {
        guard option.category == category else { return false }
        if forbidden.contains(value) { return true }
        if let mode = TaskPermissionMode(rawValue: value) {
            if let mappings = option.permissionMappings {
                guard let wire = mappings[value], !forbidden.contains(wire) else { return true }
                if let wireMode = TaskPermissionMode.migrating(wire),
                    forbidden.contains(where: { TaskPermissionMode.migrating($0) == wireMode })
                {
                    return true
                }
            }
            return forbidden.contains { TaskPermissionMode.migrating($0) == mode }
        }
        return TaskPermissionMode.migrating(value).map { mode in
            forbidden.contains { TaskPermissionMode.migrating($0) == mode }
        } ?? false
    }

    static func enforce(on session: SessionModel) async {
        guard let raw = session.state.configOptions.first(where: { $0.category == category }),
            case .select(let wire, _) = raw.kind,
            let option = session.permissionOptions(session.state.configOptions).first(where: { $0.category == category }
            ),
            case .select(let current, let choices) = option.kind,
            forbids(option, value: current) || forbids(raw, value: wire)
        else { return }
        let rank = TaskPermissionMode.migrating(current)?.rank ?? 0
        let allowed = choices.reversed().first {
            guard let mode = TaskPermissionMode(rawValue: $0.value) else { return false }
            return mode.rank <= rank && !forbids(option, value: $0.value)
        }
        if let allowed { await session.setConfigOption(option, to: allowed.value) }
    }
}
