import ACP
import Foundation
import NativeHostProtocol

/// Which host-protocol methods a paired device may call, checked by the gateway before a request
/// reaches the host (which checks its `ClientGrants` again). Local clients aren't filtered; paired
/// devices get the session methods and what their grants add (`docs/companion.md`, "Security", and
/// the grant table in `docs/durability.md`). Anything not listed is refused until a grant covers it.
public enum LinkMethodPolicy {
    /// What every paired device may do: follow and drive tasks (agents included), see updates, and
    /// browse plugins.
    static let standardMethods: Set<String> = {
        typealias Method = HostProtocol.Method
        return [
            Method.initialize, Method.listSessions, Method.newSession, Method.openSession, Method.attach,
            Method.detach, Method.prompt, Method.cancel, Method.setConfigOption, Method.respondPermission,
            Method.respondQuestion, Method.runHidden, Method.closeSession, Method.updateQueued, Method.removeQueued,
            Method.restoreQueued, Method.moveQueued, Method.sendQueuedNow, Method.listActivity, Method.updateStatus,
            Method.updateCheck, Method.listPlugins, Method.pluginAsset, Method.listAgents, Method.startAgent,
            Method.authenticateAgent, Method.listAgentSessions, Method.hostStatus, Method.doctor,
            Method.listNotifications, Method.acknowledgeNotifications, Method.actOnNotification,
            Method.checkAgentSignIn, Method.cancelAgentSignIn, Method.setSessionTitle,
        ]
    }()

    /// What `manageHost` adds: changing how the host itself runs (titles included), and the accounts
    /// its agents use.
    static let hostMethods: Set<String> = [
        HostProtocol.Method.updateInstall, HostProtocol.Method.setKeepAwake, HostProtocol.Method.setAgentCredential,
        HostProtocol.Method.removeAgentCredential, HostProtocol.Method.configureTitles,
    ]

    /// What `runCommands` adds: commands, files and projects on the host; a session's MCP servers,
    /// since a stdio server is a command the agent starts; and the agent catalog, whose specs are
    /// commands the host launches (a headless host's comes from the Mac driving it).
    static let commandPrefixes = ["_native/exec/", "_native/fs/", "_native/projects/"]
    static let commandMethods: Set<String> = [HostProtocol.Method.setMCPServers, HostProtocol.Method.syncAgents]

    /// Never over a link, whatever the grants: stopping the host belongs to the machine (remote
    /// updates go through `update/install`), and only the Mac app on the machine reports Sparkle's
    /// status.
    static let localOnlyMethods: Set<String> = [
        HostProtocol.Method.shutdown, HostProtocol.Method.updateReport,
    ]

    public static func allows(_ method: String, with grants: LinkGrants) -> Bool {
        guard !localOnlyMethods.contains(method) else { return false }
        if method == HostProtocol.Method.setPluginEnabled { return grants.managePlugins }
        if hostMethods.contains(method) { return grants.manageHost }
        if commandMethods.contains(method) || commandPrefixes.contains(where: method.hasPrefix) {
            return grants.runCommands
        }
        return standardMethods.contains(method)
    }

    /// `allows(_:with:)`, plus what a request's params ask for beyond its method: MCP servers or agent
    /// options that start commands (`HostProtocol.sessionRequestRunsCommands`), or the record of the
    /// commands clients ran. Both take `runCommands`.
    public static func allows(_ method: String, params: JSONValue?, with grants: LinkGrants) -> Bool {
        guard allows(method, with: grants) else { return false }
        guard !grants.runCommands else { return true }
        typealias Method = HostProtocol.Method
        switch method {
        case Method.newSession, Method.openSession, Method.setMCPServers:
            var servers: [JSONValue] = []
            if case .array(let listed)? = params?["mcpServers"] { servers = listed }
            return !HostProtocol.sessionRequestRunsCommands(mcpServers: servers, meta: params?["meta"])
        case Method.listActivity:
            return params?["includeCommands"] != .bool(true)
        default:
            return true
        }
    }
}
