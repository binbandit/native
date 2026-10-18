import Foundation
import NativeHostProtocol

/// Which host-protocol methods a paired device may call, checked by the gateway before a request
/// reaches the host. Local clients aren't filtered; paired devices get what their role allows
/// (`docs/companion.md`, "Security").
public enum LinkMethodPolicy {
    /// What the companion needs to follow and drive tasks, see updates, and browse plugins.
    static let companionMethods: Set<String> = {
        typealias Method = HostProtocol.Method
        return [
            Method.initialize, Method.listSessions, Method.newSession, Method.openSession, Method.attach,
            Method.detach, Method.prompt, Method.cancel, Method.setConfigOption, Method.respondPermission,
            Method.closeSession, Method.updateQueued, Method.removeQueued, Method.sendQueuedNow, Method.listActivity,
            // Designed with the updates and plugins work: reading state, and installing an update.
            "_native/host/update/status", "_native/host/update/install", "_native/plugins/list",
            "_native/plugins/asset",
        ]
    }()

    /// Never over a link, whatever the role: stopping or restarting the host belongs to the machine
    /// (remote updates go through `_native/host/update/install`), and agents come from the host's
    /// own plugins, so a device never replaces its catalog.
    static let localOnlyMethods: Set<String> = [HostProtocol.Method.shutdown, HostProtocol.Method.syncAgents]

    public static func allows(_ method: String, for role: LinkDeviceRole) -> Bool {
        guard !localOnlyMethods.contains(method) else { return false }
        switch role {
        case .admin: return true
        case .companion: return companionMethods.contains(method)
        case .unknown: return false
        }
    }
}
