import ACP
import NativeHostProtocol

extension HostCore {
    /// The host checks its own cap, including when a companion has no managed policy of its own.
    func requirePermission(in session: HostSession, value: String? = nil, intent: String? = nil) throws {
        guard !policy.forbiddenPermissionModes.isEmpty else { return }
        let current = session.mirror.state.configOptions.first { $0.category == "mode" }.flatMap { option -> String? in
            guard case .select(let current, _) = option.kind else { return nil }
            return current
        }
        let selectedIntent =
            value == nil ? session.record.configChoices[SetConfigOptionParams.permissionChoiceKey] : intent
        guard let value = value ?? current,
            policy.allowsPermission(
                value, intent: selectedIntent)
        else {
            throw HostPolicyDenial("use this task's permissions", policy: policy)
        }
    }
}
