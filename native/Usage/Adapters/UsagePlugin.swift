import ACP
import Foundation

/// Usage limits and context reports, fed by session events: tells the user when a provider's
/// usage limit is close or reached, picks stopped sessions back up at the reset, and keeps each
/// session's `/context` breakdown.
struct UsagePlugin: NativePlugin {
    let manifest = PluginManifest(
        id: "usage",
        name: "Usage",
        description:
            "Tells you when an agent's usage limit is close or reached, picks stopped sessions back up when it resets, and breaks down what fills each session's context."
    )

    let limits: UsageLimits
    let contextReports: ContextReports
    private let clockEvents: SystemClockEvents

    init() {
        let limits = UsageLimits(store: UsageLimitsFileStore(), alerts: UserNotificationAlerts())
        self.limits = limits
        contextReports = ContextReports()
        clockEvents = SystemClockEvents { [weak limits] in limits?.processDue() }
    }

    func handle(_ event: SessionEvent) async {
        switch event {
        case .usageUpdated(let session, let usage):
            if let info = usage.rateLimit {
                limits.record(info, agent: session.agent, agentName: session.agentName)
            }
        case .turnFailed(let session, let prompt, let error, let items):
            limits.recordFailure(
                FailedTurn(prompt: prompt, items: items), error: error, agent: session.agent,
                agentName: session.agentName, stopping: LimitTarget(session))
        case .turnEnded(let session, let reason):
            if let target = LimitTarget(session) {
                limits.recordTurnEnded(reason, in: target)
            }
            if let id = session.sessionID {
                contextReports.noteTurnEnded(SessionKey(agent: session.agent, id: id))
            }
        default:
            break
        }
    }
}

extension BuiltInPlugins {
    /// One instance for the app: the composition root sets `usage.limits.host`, and views read the
    /// same limits and reports the plugin is fed.
    static let usage = UsagePlugin()
}
