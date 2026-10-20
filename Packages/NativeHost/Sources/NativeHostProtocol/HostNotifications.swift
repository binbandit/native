import ACP
import Foundation

// Notifications as host events (docs/durability.md, "Notifications"). The host turns what needs the
// user, and what finished or failed, into numbered notifications in a bounded backlog, whether or
// not a client is attached. Each client shows them its own way (the Mac's notification center, the
// phone's pushes) and acknowledges them, so one seen on one device clears on the others.

extension HostProtocol.Method {
    // Client → host requests.
    public static let listNotifications = "_native/notifications/list"
    public static let acknowledgeNotifications = "_native/notifications/acknowledge"
    public static let actOnNotification = "_native/notifications/act"

    // Host → client notifications.
    public static let notificationPosted = "_native/notifications/posted"
    public static let notificationsCleared = "_native/notifications/cleared"
}

/// Something a host's sessions did that the user may want to hear about away from the task.
public struct HostNotification: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, WireEnum {
        /// A tool call waits for the user's approval.
        case permission
        /// The agent asked the user something (a form).
        case question
        case turnFinished
        case turnFailed
        /// A turn stopped on the provider's usage limit.
        case limitReached
        /// A turn was cut off and Native did something about it (`recovery` says what).
        case recovered
        case unknown
    }

    /// What a client can offer on the notification; `_native/notifications/act` does it.
    public enum Action: String, WireEnum {
        /// Approve once (or always, when the agent offers nothing narrower).
        case allow
        case reject
        /// Answer a question that takes one line of text.
        case reply
        case unknown
    }

    /// Whether it's still news.
    public enum State: String, WireEnum {
        case active
        /// The user saw it on some client: opened, answered or dismissed it, or wrote to the task.
        case acknowledged
        /// What it asked for is over: the approval or question was answered (anywhere) or withdrawn.
        case resolved
        case unknown
    }

    /// Stable and increasing on its host, across restarts; clients key notifications by
    /// `(HostID, id)`.
    public var id: Int64
    public var at: Date
    public var kind: Kind
    public var state: State
    public var sessionID: HostSessionID
    /// The task a subagent belongs to; notifications about a subagent open that task.
    public var parentID: HostSessionID?
    public var agentID: String
    public var agentName: String
    public var agentSessionID: SessionID?
    public var parentAgentSessionID: SessionID?
    /// The task's title at the time (the parent's, for a subagent).
    public var title: String?
    /// The tool call's title, the question, why the turn failed, or the provider's limit message.
    public var detail: String?
    public var actions: [Action]
    /// For a permission: the agent's option each action picks, so a client following the session
    /// can also answer with `_native/session/respond_permission`.
    public var toolCallID: String?
    public var allowOptionID: String?
    public var rejectOptionID: String?
    /// For a question: the host's id for it, and its one free-text field when `reply` can answer it.
    public var questionID: String?
    public var replyField: String?
    /// For a finished turn: how long it took and how many files it changed.
    public var duration: TimeInterval?
    public var changedFiles: Int?
    /// For a limit: when it resets, if the provider said.
    public var resetsAt: Date?
    public var recovery: RecoveryNote?
    /// When it stopped being news, and the client that cleared it ("Brayden's iPhone"), if one did.
    public var clearedAt: Date?
    public var clearedBy: String?

    public init(
        id: Int64 = 0, at: Date = .now, kind: Kind, state: State = .active, sessionID: HostSessionID,
        parentID: HostSessionID? = nil, agentID: String, agentName: String, agentSessionID: SessionID?,
        parentAgentSessionID: SessionID? = nil, title: String?, detail: String? = nil, actions: [Action] = []
    ) {
        self.id = id
        self.at = at
        self.kind = kind
        self.state = state
        self.sessionID = sessionID
        self.parentID = parentID
        self.agentID = agentID
        self.agentName = agentName
        self.agentSessionID = agentSessionID
        self.parentAgentSessionID = parentAgentSessionID
        self.title = title
        self.detail = detail
        self.actions = actions
    }

    /// The task the notification opens: the session, or a subagent's parent.
    public var taskID: HostSessionID {
        parentID ?? sessionID
    }

    /// Notifications in one group replace each other on a client (an APNs collapse id): one per
    /// task, and one per provider for limits, which every task of the agent shares.
    public var group: String {
        kind == .limitReached ? "limit.\(agentID)" : "task.\(taskID)"
    }

    /// Whether the task waits on the user until it's answered.
    public var waitsOnUser: Bool {
        kind == .permission || kind == .question
    }
}

// MARK: - Requests

public struct ListNotificationsParams: Codable, Sendable {
    /// Only notifications numbered after this one; nil for the oldest kept.
    public var after: Int64?
    public var limit: Int

    public init(after: Int64? = nil, limit: Int = 200) {
        self.after = after
        self.limit = limit
    }
}

public struct HostNotificationList: Codable, Sendable {
    /// Those after `after`, oldest first, whatever their state.
    public var notifications: [HostNotification]
    /// Every notification in the backlog that's still news, oldest first, so a client can clear
    /// what was cleared elsewhere while it was away.
    public var active: [HostNotification]
    /// The newest notification the host has numbered, kept or not; nil before the first.
    public var latestID: Int64?

    public init(notifications: [HostNotification], active: [HostNotification], latestID: Int64?) {
        self.notifications = notifications
        self.active = active
        self.latestID = latestID
    }
}

/// Marks notifications seen. Older active ones in the same groups go with them: a client showed
/// only the newest of each group.
public struct AcknowledgeNotificationsParams: Codable, Sendable {
    public var ids: [Int64]

    public init(ids: [Int64]) {
        self.ids = ids
    }
}

/// Does what the user picked on a notification, then acknowledges it. Allow and reject answer the
/// permission as `_native/session/respond_permission` would; reply answers the question.
public struct ActOnNotificationParams: Codable, Sendable {
    public var id: Int64
    public var action: HostNotification.Action
    /// The answer, for `reply`.
    public var text: String?

    public init(id: Int64, action: HostNotification.Action, text: String? = nil) {
        self.id = id
        self.action = action
        self.text = text
    }
}

public struct ActOnNotificationResult: Codable, Sendable {
    public enum Outcome: String, WireEnum {
        case done
        /// Answered on another client, or withdrawn, before this got there.
        case alreadyAnswered
        /// The notification can't do it (a question with more than one field, an empty reply):
        /// open the task instead.
        case openTask
        /// The host no longer has the notification (older than its backlog).
        case expired
        case unknown
    }

    public var outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }
}

// MARK: - Host → client

public struct NotificationPostedMessage: Codable, Sendable {
    public var notification: HostNotification

    public init(notification: HostNotification) {
        self.notification = notification
    }
}

/// Notifications that stopped being news; clients take them down.
public struct NotificationsClearedMessage: Codable, Hashable, Sendable {
    public var ids: [Int64]
    public var state: HostNotification.State
    /// The client that cleared them, if one did.
    public var by: String?

    public init(ids: [Int64], state: HostNotification.State, by: String? = nil) {
        self.ids = ids
        self.state = state
        self.by = by
    }
}

// MARK: - Questions

extension CreateElicitationRequest {
    /// The form's one field, when it has exactly one and it takes free text: a question a line of
    /// text answers, from a notification's reply field.
    public var singleTextField: String? {
        guard case .object(let properties)? = requestedSchema?["properties"], properties.count == 1,
            let (name, field) = properties.first, field["type"]?.stringValue == "string", field["enum"] == nil
        else { return nil }
        return name
    }
}
