import ACP
import Foundation

/// Usage limits, context reports and notifications, fed by session events: tells the user when a
/// provider's usage limit is close or reached and picks stopped tasks back up at the reset, keeps
/// each task's `/context` breakdown, and notifies about long work and tasks that need the user.
struct UsagePlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "usage",
        name: "Usage",
        description:
            "Tells you when an agent's usage limit is close or reached, picks stopped tasks back up when it resets, breaks down what fills each task's context, and notifies you when long work finishes or a task needs you."
    )

    let limits: UsageLimits
    let contextReports = ContextReports()
    let providerReports = ProviderUsageReports()
    let notifications: UsageNotifications
    let activity = ActivityLog(store: ActivityFileStore())
    private let clockEvents: SystemClockEvents

    init() {
        let notifications = UsageNotifications(poster: UserNotificationPoster(), activity: PlatformAppActivity())
        let limits = UsageLimits(store: UsageLimitsFileStore(), alerts: notifications)
        self.notifications = notifications
        self.limits = limits
        clockEvents = SystemClockEvents { [weak limits] in limits?.processDue() }
    }

    /// Gives Usage the app to act on; resumes that came due before this run then.
    func connect(to host: some UsageHost) {
        notifications.host = host
        providerReports.host = host
        limits.host = host
        activity.backfill(host.activityBackfill())
    }

    /// Opens a task from Settings › Usage's day list.
    func open(_ task: ActivityDay.Task) {
        let ref = UsageSessionRef(
            agent: AgentDefinition.ID(rawValue: task.agent), agentName: task.agentName, session: SessionID(task.session),
            title: task.title)
        notifications.host?.show(ref)
    }

    func handle(_ event: SessionEvent) async {
        switch event {
        case .usageUpdated(let session, let usage):
            activity.recordUsage(session, usage)
            if let info = usage.rateLimit {
                limits.record(info, agent: session.agent, agentName: session.agentName)
            }
        case .turnFailed(let session, let prompt, let error, let items):
            limits.recordFailure(
                FailedTurn(prompt: prompt, items: items), error: error, agent: session.agent,
                agentName: session.agentName, stopping: UsageSessionRef(session))
        case .turnEnded(let session, let reason):
            if let ref = UsageSessionRef(session) {
                limits.recordTurnEnded(reason, in: ref)
                contextReports.noteTurnEnded(SessionKey(agent: ref.agent, id: ref.session))
            }
            let duration = UsageSessionRef(session).flatMap { notifications.host?.lastTurnSummary(of: $0)?.duration }
            activity.recordTurn(session, duration: duration)
            await notifications.turnEnded(session, reason: reason)
        case .permissionRequested(let session, let toolCall):
            await notifications.permissionRequested(session, toolCall: toolCall)
        case .questionAsked(let session, let message):
            await notifications.questionAsked(session, message: message)
        case .needsUser(let session, let reason):
            await notifications.needsAttention(.needsUser, context: session, reason: reason)
        case .failed(let session, let reason):
            await notifications.needsAttention(.failed, context: session, reason: reason)
        case .sessionStarted(let session):
            activity.recordSessionStarted(session)
        case .promptSent(let session, _):
            activity.recordPrompt(session)
        }
    }
}

extension BuiltInPlugins {
    /// One instance for the app: the composition root connects it, and views read the same limits
    /// and reports the plugin is fed.
    static let usage = UsagePlugin()
}
