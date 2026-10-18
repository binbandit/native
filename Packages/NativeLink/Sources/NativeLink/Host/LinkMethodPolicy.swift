import Foundation
import NativeHostProtocol

/// Which host-protocol methods a paired device may call, checked by the gateway before a request
/// reaches the host (which checks its `ClientGrants` again). Local clients aren't filtered; paired
/// devices get the session methods and what their grants add (`docs/companion.md`, "Security").
/// Anything not listed, including future commands and file access, is refused until a grant covers it.
public enum LinkMethodPolicy {
    /// What every paired device may do: follow and drive tasks, see updates, and browse plugins.
    static let standardMethods: Set<String> = {
        typealias Method = HostProtocol.Method
        return [
            Method.initialize, Method.listSessions, Method.newSession, Method.openSession, Method.attach,
            Method.detach, Method.prompt, Method.cancel, Method.setConfigOption, Method.respondPermission,
            Method.closeSession, Method.updateQueued, Method.removeQueued, Method.sendQueuedNow, Method.listActivity,
            // Designed with the updates and plugins work: reading state, and installing an update.
            "_native/host/update/status", "_native/host/update/install", Method.listPlugins, Method.pluginAsset,
        ]
    }()

    /// Never over a link, whatever the role: stopping or restarting the host belongs to the machine
    /// (remote updates go through `_native/host/update/install`), and agents come from the host's
    /// own plugins, so a device never replaces its catalog.
    static let localOnlyMethods: Set<String> = [HostProtocol.Method.shutdown, HostProtocol.Method.syncAgents]

    public static func allows(_ method: String, with grants: LinkGrants) -> Bool {
        guard !localOnlyMethods.contains(method) else { return false }
        if method == HostProtocol.Method.setPluginEnabled { return grants.managePlugins }
        return standardMethods.contains(method)
    }
}
