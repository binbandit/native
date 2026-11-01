import ACP
import NativeHostProtocol

extension HostCore {
    func hasDeniedPermissions(in session: HostSession) -> Bool {
        (try? requirePermission(in: session)) == nil
            || session.pendingPermissionChanges.values.contains {
                (try? requirePermission(in: session, value: $0.value, intent: $0.intent)) == nil
            }
    }

    /// The host checks its own cap, including when a companion has no managed policy of its own.
    func requirePermission(
        in session: HostSession, value: String? = nil, intent: String? = nil, replacingIntent: Bool = false
    ) throws {
        guard !policy.forbiddenPermissionModes.isEmpty else { return }
        let current = session.mirror.state.configOptions.first { $0.category == "mode" }.flatMap { option -> String? in
            guard case .select(let current, _) = option.kind else { return nil }
            return current
        }
        let selectedIntent =
            value == nil && !replacingIntent
            ? session.record.configChoices[SetConfigOptionParams.permissionChoiceKey] : intent
        guard let value = value ?? current,
            policy.allowsPermission(
                value, intent: selectedIntent)
        else {
            throw HostPolicyDenial("use this task's permissions", policy: policy)
        }
    }
}
