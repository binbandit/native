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
            Method.updateStatus, Method.updateCheck, Method.listPlugins, Method.pluginAsset,
        ]
    }()

    /// Never over a link, whatever the grants: stopping the host belongs to the machine (remote
    /// updates go through `update/install`), agents come from the host's own plugins so a device
    /// never replaces its catalog, and only the Mac app on the machine reports Sparkle's status.
    static let localOnlyMethods: Set<String> = [
        HostProtocol.Method.shutdown, HostProtocol.Method.syncAgents, HostProtocol.Method.updateReport,
    ]

    public static func allows(_ method: String, with grants: LinkGrants) -> Bool {
        guard !localOnlyMethods.contains(method) else { return false }
        if method == HostProtocol.Method.setPluginEnabled { return grants.managePlugins }
        if method == HostProtocol.Method.updateInstall { return grants.manageHost }
        return standardMethods.contains(method)
    }
}
