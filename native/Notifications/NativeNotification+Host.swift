import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol

// A host's notifications on this Mac, in the words Native's own notifications use, so a task reads
// the same whichever path told the user about it.
extension NativeNotification {
    /// How this Mac shows `notification` from host `hostID`. `hostName` names a host other than this
    /// Mac, so the user can tell where the task runs. Nil for kinds this Mac doesn't show.
    init?(_ notification: HostNotification, hostID: NativeHostProtocol.HostID, hostName: String?, now: Date = .now) {
        guard let ref = notification.ref else { return nil }
        switch notification.kind {
        case .permission:
            self = .permission(ref, toolCall: notification.detail ?? "Tool call")
            actions = notification.actions.compactMap(Action.init(host:))
        case .question:
            self = .question(ref, message: notification.detail ?? "", canReply: notification.actions.contains(.reply))
        case .turnFinished:
            self = .turnFinished(
                ref, duration: notification.duration, changedFiles: notification.changedFiles ?? 0)
        case .turnFailed:
            self = .attention(.failed, ref: ref, reason: notification.detail ?? "The turn failed.")
        case .limitReached:
            let limit = ProviderLimit(
                agent: ref.agent, agentName: ref.agentName, status: .reached, window: nil,
                resetsAt: notification.resetsAt, utilization: nil, message: notification.detail,
                updatedAt: notification.at)
            self.init(.reached(limit, sessions: [ref]), now: now)
            // Resume at Reset belongs to the limits this Mac tracks itself; opening the task is the way on.
            actions = []
        case .recovered:
            guard let note = notification.recovery else { return nil }
            self = .attention(.failed, ref: ref, reason: note.sentence { DSFormat.time($0, now: now) })
        case .unknown:
            return nil
        }
        id = Self.identifier(host: hostID, group: notification.group)
        self.hostID = hostID.description
        hostNotificationID = notification.id
        if let hostName {
            subtitle = "\(notification.agentName) on \(hostName)"
        }
    }

    /// "While you were away": what a host's tasks did while this Mac wasn't connected, in one
    /// notification instead of one for each. `hostName` names a host other than this Mac.
    static func away(_ summary: AwaySummary, hostID: NativeHostProtocol.HostID, hostName: String?) -> NativeNotification
    {
        NativeNotification(
            id: "native.host.\(hostID).away", kind: .awaySummary, agent: "", agentName: "Native",
            title: hostName.map { "While you were away from \($0)" } ?? "While you were away",
            body: summary.headline, sound: summary.items.contains(where: \.needsUser) ? .needsYou : .none)
    }

    /// One per host and group: a newer notification about a task replaces the older one.
    static func identifier(host: NativeHostProtocol.HostID, group: String) -> String {
        "native.host.\(host).\(group)"
    }
}

extension NativeNotification.Action {
    init?(host action: HostNotification.Action) {
        switch action {
        case .allow: self = .allow
        case .reject: self = .reject
        case .reply: self = .reply
        case .unknown: return nil
        }
    }
}

extension HostNotification {
    /// The task as Usage and the sidebar know it: its agent and the agent's session id.
    var ref: UsageSessionRef? {
        guard let session = agentSessionID else { return nil }
        return UsageSessionRef(
            agent: AgentDefinition.ID(rawValue: agentID), agentName: agentName, session: session, title: title,
            parent: parentAgentSessionID)
    }
}
