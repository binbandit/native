import ACP
import Foundation
import NativeHostProtocol

// Notifications as host events (docs/durability.md, "Notifications"): what a session's events mean
// for a user who isn't looking, posted to every client and kept in a bounded backlog in the store, so
// a client that wasn't connected catches up and a phone can be told. A notification stops being news
// when a client acknowledges it, the user writes to its task, or what it asked for settles (an
// approval answered anywhere, or withdrawn); every client hears so and takes it down.
extension HostCore {
    /// How many notifications the store keeps; older ones drop off.
    static let notificationBacklog = 200

    /// Turns one of Native's own session events into a notification, or clears the ones it settles.
    func noteForNotifications(_ payload: HostEvent.Payload, in session: HostSession) {
        switch payload {
        case .permissionRequested(let toolCallID, let request):
            postPermission(toolCallID: toolCallID, request: request, in: session)
        case .permissionResolved(let toolCallID, _):
            clearNotifications(as: .resolved) {
                $0.sessionID == session.id && $0.kind == .permission && $0.toolCallID == toolCallID
            }
        case .questionAsked(let questionID, let request):
            postQuestion(questionID: questionID, request: request, in: session)
        case .questionResolved(let questionID):
            clearNotifications(as: .resolved) {
                $0.sessionID == session.id && $0.kind == .question && $0.questionID == questionID
            }
        case .turnEnded(let stopReason) where stopReason == "end_turn":
            postTurnFinished(in: session)
        case .turnFailed(let message, let error, _):
            postTurnFailed(message: message, error: error, in: session)
        case .recovered(let note):
            guard var notification = notification(.recovered, about: session) else { return }
            notification.recovery = note
            notification.detail = note.problem
            post(notification)
        case .prompt(let echo) where echo.origin == .user:
            // The user wrote to the task, from whichever client: what it said before has been seen.
            clearNotifications(as: .acknowledged) { $0.taskID == session.id && !$0.waitsOnUser }
        default:
            break
        }
    }

    /// At startup: the previous run's approvals and questions died with its agents, which ask again
    /// once their sessions resume, so their notifications are over.
    func resolveNotificationsOfPreviousRun() {
        clearNotifications(as: .resolved) { $0.waitsOnUser }
    }

    // MARK: - Requests

    func listNotifications(_ params: ListNotificationsParams) throws -> HostNotificationList {
        HostNotificationList(
            notifications: try store.notifications(
                after: params.after, limit: min(max(params.limit, 0), Self.notificationBacklog)),
            active: try store.activeNotifications(), latestID: try store.latestNotificationID())
    }

    /// A client showed these and the user saw them. Older active notifications in their groups go too:
    /// the client showed only the newest of each.
    func acknowledgeNotifications(_ ids: [Int64], by client: ClientLink?) throws {
        let acknowledged = Set(ids)
        var newest: [String: Int64] = [:]
        for notification in try store.activeNotifications() where acknowledged.contains(notification.id) {
            newest[notification.group] = max(newest[notification.group] ?? 0, notification.id)
        }
        clearNotifications(as: .acknowledged, by: client) { notification in
            acknowledged.contains(notification.id) || newest[notification.group].map { notification.id < $0 } == true
        }
    }

    /// Does what the user picked on a notification on some client, then acknowledges it.
    func actOnNotification(
        _ params: ActOnNotificationParams, by client: ClientLink?
    ) throws
        -> ActOnNotificationResult
    {
        guard let notification = try store.notification(params.id) else {
            return ActOnNotificationResult(outcome: .expired)
        }
        let outcome = try perform(params, on: notification)
        try acknowledgeNotifications([notification.id], by: client)
        return ActOnNotificationResult(outcome: outcome)
    }

    private func perform(
        _ params: ActOnNotificationParams, on notification: HostNotification
    ) throws
        -> ActOnNotificationResult.Outcome
    {
        guard notification.state != .resolved, let session = sessions[notification.sessionID] else {
            return .alreadyAnswered
        }
        switch (params.action, notification.kind) {
        case (.allow, .permission), (.reject, .permission):
            guard let toolCallID = notification.toolCallID, session.pendingPermissions[toolCallID] != nil else {
                return .alreadyAnswered
            }
            let option = params.action == .allow ? notification.allowOptionID : notification.rejectOptionID
            guard let option else { return .openTask }
            try respondPermission(
                RespondPermissionParams(sessionID: session.id, toolCallID: toolCallID, optionID: option))
            return .done
        case (.reply, .question):
            guard let questionID = notification.questionID,
                session.pendingQuestions.contains(where: { $0.id == questionID })
            else { return .alreadyAnswered }
            let text = params.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let field = notification.replyField, !text.isEmpty else { return .openTask }
            let response = JSONValue.object(["action": .string("accept"), "content": .object([field: .string(text)])])
            try respondQuestion(
                RespondQuestionParams(sessionID: session.id, questionID: questionID, response: response))
            return .done
        default:
            return .openTask
        }
    }

    // MARK: - Posting

    private func postPermission(toolCallID: String, request: JSONValue, in session: HostSession) {
        guard var notification = notification(.permission, about: session) else { return }
        let decoded = Self.decode(RequestPermissionRequest.self, from: request)
        let options = decoded?.options ?? []
        func option(_ kinds: [PermissionOption.Kind]) -> String? {
            kinds.lazy.compactMap { kind in options.first { $0.kind == kind }?.optionId }.first
        }
        notification.toolCallID = toolCallID
        notification.detail = decoded?.toolCall.title
        notification.allowOptionID = option([.allowOnce, .allowAlways])
        notification.rejectOptionID = option([.rejectOnce, .rejectAlways])
        notification.actions =
            (notification.allowOptionID == nil ? [] : [.allow]) + (notification.rejectOptionID == nil ? [] : [.reject])
        post(notification)
    }

    private func postQuestion(questionID: String, request: JSONValue, in session: HostSession) {
        guard var notification = notification(.question, about: session) else { return }
        let decoded = Self.decode(CreateElicitationRequest.self, from: request)
        notification.questionID = questionID
        notification.detail = decoded?.message
        notification.replyField = decoded?.singleTextField
        notification.actions = notification.replyField == nil ? [] : [.reply]
        post(notification)
    }

    private func postTurnFinished(in session: HostSession) {
        // A subagent's turn is part of its parent's, which says when it's done.
        guard session.record.parentID == nil, var notification = notification(.turnFinished, about: session) else {
            return
        }
        let state = session.mirror.state
        if let turn = state.turns.last {
            let summary = state.summary(of: turn)
            notification.duration = summary.duration
            notification.changedFiles = summary.changedFiles.count
        }
        post(notification)
    }

    private func postTurnFailed(message: String, error: RPCError?, in session: HostSession) {
        // A passing failure goes out again by itself (`retryAt`); only one that waits on the user is news.
        guard session.retryAt == nil, session.record.parentID == nil else { return }
        let limit = error.flatMap { UsageLimitHit(error: $0) } ?? UsageLimitHit(text: message)
        guard var notification = notification(limit == nil ? .turnFailed : .limitReached, about: session) else {
            return
        }
        notification.detail = limit?.message ?? message
        notification.resetsAt = limit?.resetsAt
        post(notification)
    }

    /// A notification about `session`, filled in with its task and what clients name it (the user's
    /// title, the generated one, the agent's, then its first message). Nil for tasks Native's tools started
    /// (workflow steps, orchestration), which report through their run instead.
    private func notification(_ kind: HostNotification.Kind, about session: HostSession) -> HostNotification? {
        let task = session.record.parentID.flatMap { sessions[$0] } ?? session
        guard session.record.origin != .task, task.record.origin != .task else { return nil }
        let isSubagent = task !== session
        return HostNotification(
            kind: kind, sessionID: session.id, parentID: isSubagent ? task.id : nil, agentID: session.record.agentID,
            agentName: session.agentName, agentSessionID: session.record.agentSessionID,
            parentAgentSessionID: isSubagent ? task.record.agentSessionID : nil, title: task.displayTitle)
    }

    private func post(_ notification: HostNotification) {
        let stored: HostNotification
        do {
            stored = try store.addNotification(notification, keeping: Self.notificationBacklog)
        } catch {
            logger.error("Couldn't keep a notification: \(error.localizedDescription)")
            return
        }
        let message = NotificationPostedMessage(notification: stored)
        for client in clients.values {
            client.notify(HostProtocol.Method.notificationPosted, message)
        }
    }

    /// Marks the active notifications `matches` picks as no longer news, and tells every client.
    private func clearNotifications(
        as state: HostNotification.State, by client: ClientLink? = nil, where matches: (HostNotification) -> Bool
    ) {
        let name = client?.info?.name
        do {
            let cleared = try store.activeNotifications().filter(matches).map { notification in
                var notification = notification
                notification.state = state
                notification.clearedAt = .now
                notification.clearedBy = name
                return notification
            }
            guard !cleared.isEmpty else { return }
            try store.updateNotifications(cleared)
            let message = NotificationsClearedMessage(ids: cleared.map(\.id), state: state, by: name)
            for client in clients.values {
                client.notify(HostProtocol.Method.notificationsCleared, message)
            }
        } catch {
            logger.error("Couldn't clear notifications: \(error.localizedDescription)")
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from json: JSONValue) -> Value? {
        (try? JSONEncoder().encode(json)).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }
}
