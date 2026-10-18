import ACP
import Foundation

/// Decides which events become notifications and acts on what the user picks in them. Notifies
/// only for long work and for the moments a task waits on the user, and never about a task the
/// user is already looking at.
final class UsageNotifications: LimitAlerting {
    /// Limit actions go back to `UsageLimits`, which sets this.
    var onAction: ((LimitAlertAction) -> Void)?
    weak var host: (any UsageNotificationsHost)?

    private let poster: any NativeNotificationPosting
    private let activity: any AppActivity
    private let preferences: NotificationPreferences
    private let now: () -> Date

    init(
        poster: any NativeNotificationPosting, activity: any AppActivity,
        preferences: NotificationPreferences = NotificationPreferences(), now: @escaping () -> Date = Date.init
    ) {
        self.poster = poster
        self.activity = activity
        self.preferences = preferences
        self.now = now
        poster.onResponse = { [weak self] response in self?.receive(response) }
    }

    // MARK: - Events

    func post(_ alert: LimitAlert) async {
        guard preferences.notifiesUsageLimits else { return }
        let notification = NativeNotification(alert, now: now())
        // The session's banner and transcript card say it all while the user is in Native.
        if !notification.isAlwaysShown, activity.isActive { return }
        await poster.post(notification)
    }

    func turnEnded(_ context: SessionContext, reason: StopReason) async {
        // A subagent's turn is part of its parent's, which notifies when it finishes.
        guard reason == .endTurn, preferences.notifiesLongWork, let ref = UsageSessionRef(context), ref.parent == nil,
            isUsersTask(ref), let summary = host?.lastTurnSummary(of: ref), let duration = summary.duration,
            duration >= preferences.longWorkThreshold
        else { return }
        await deliver(.turnFinished(ref, summary: summary), unlessShowing: ref)
    }

    func permissionRequested(_ context: SessionContext, toolCall: String) async {
        guard preferences.notifiesNeedsYou, let ref = UsageSessionRef(context), isUsersTask(ref) else { return }
        await deliver(.permission(ref, toolCall: toolCall), unlessShowing: ref)
    }

    func questionAsked(_ context: SessionContext, message: String) async {
        guard preferences.notifiesNeedsYou, let ref = UsageSessionRef(context), isUsersTask(ref) else { return }
        let canReply = host?.canReplyInText(ref) ?? false
        await deliver(.question(ref, message: message, canReply: canReply), unlessShowing: ref)
    }

    func needsAttention(_ kind: NativeNotification.Kind, context: SessionContext?, reason: String) async {
        guard preferences.notifiesNeedsYou else { return }
        let ref = context.flatMap(UsageSessionRef.init)
        if let ref, !isUsersTask(ref) { return }
        await deliver(.attention(kind, ref: ref, reason: reason), unlessShowing: ref)
    }

    /// Tasks Native's tools started (workflow steps, orchestration, expeditions) report through
    /// their run instead.
    private func isUsersTask(_ ref: UsageSessionRef) -> Bool {
        host?.isNativeTask(ref) != true
    }

    /// Skips the notification while the user is in Native looking at the task, or at Native at all
    /// when it isn't about one task.
    private func deliver(_ notification: NativeNotification, unlessShowing ref: UsageSessionRef?) async {
        if activity.isActive, ref.map({ host?.isShowing($0) ?? false }) ?? true { return }
        await poster.post(notification)
    }

    // MARK: - Responses

    private func receive(_ response: NativeNotificationResponse) {
        let notification = response.notification
        let agent = AgentDefinition.ID(rawValue: notification.agent)
        let ref = notification.ref
        switch response.action {
        case .resumeAtReset?:
            onAction?(.resumeAtReset(agent))
        case .snoozeUntilReset?:
            onAction?(.snoozeUntilReset(agent))
        case .allow?, .reject?:
            guard let ref else { return }
            let allow = response.action == .allow
            Task { await host?.answerPermission(of: ref, allow: allow) }
        case .reply?:
            guard let ref else { return }
            let text = response.replyText ?? ""
            Task {
                // A question the text can't answer opens instead, so the reply isn't lost on the user.
                if await host?.reply(to: ref, text: text) != true {
                    host?.show(ref)
                }
            }
        case nil:
            if let ref {
                host?.show(ref)
            }
        }
    }
}
