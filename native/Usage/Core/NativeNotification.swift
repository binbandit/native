import Foundation

/// A notification as any client shows it: the Mac's notification center now, the iPhone companion
/// later. Plain strings and enums only, so it travels between host and clients as is.
nonisolated struct NativeNotification: Codable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Sendable {
        case turnFinished, permission, question, needsUser, failed
        case limitReached, limitWarning, limitReset, limitRescheduled, resumeFailed
    }

    nonisolated enum Action: String, Codable, Sendable {
        /// Allow once, as ⌘Y does.
        case allow
        /// Reject once, as ⌘⇧⌫ does.
        case reject
        /// Answer in text.
        case reply
        case resumeAtReset
        case snoozeUntilReset
    }

    /// A client plays these its own way; the Mac leaves sound to the Sounds feature.
    nonisolated enum Sound: String, Codable, Sendable {
        case needsYou, done, none
    }

    /// A newer notification with the same id replaces the older one.
    var id: String
    var kind: Kind
    var agent: String
    var agentName: String
    var session: String?
    var parentSession: String?
    var sessionTitle: String?
    var title: String
    var subtitle: String?
    var body: String
    var actions: [Action] = []
    var sound: Sound = .none
    /// Shown even while the user is looking at the task: they asked for it, or can't see it there.
    var isAlwaysShown = false
}

/// What the user did with a notification.
nonisolated struct NativeNotificationResponse: Sendable {
    let notification: NativeNotification
    /// Nil when they clicked the notification itself.
    let action: NativeNotification.Action?
    var replyText: String?
}

/// Shows notifications and reports what the user does with them.
protocol NativeNotificationPosting: AnyObject {
    var onResponse: ((NativeNotificationResponse) -> Void)? { get set }
    func post(_ notification: NativeNotification) async
}

/// Whether the user is in Native right now. A platform adapter answers it.
protocol AppActivity: AnyObject {
    var isActive: Bool { get }
}

extension NativeNotification {
    /// Fills in who the notification is about.
    init(id: String, kind: Kind, about ref: UsageSessionRef, title: String, body: String) {
        self.init(
            id: id, kind: kind, agent: ref.agent.rawValue, agentName: ref.agentName, session: ref.session.rawValue,
            parentSession: ref.parent?.rawValue, sessionTitle: ref.title, title: title, body: body)
    }

    var ref: UsageSessionRef? {
        guard let session else { return nil }
        return UsageSessionRef(
            agent: AgentDefinition.ID(rawValue: agent), agentName: agentName, session: SessionID(session),
            title: sessionTitle, parent: parentSession.map(SessionID.init))
    }
}
