import Foundation

/// Decides which automations are due. Pure, so the schedule rules are tested without clocks, and so
/// the planner runs the same in the app today and in the durable host later.
///
/// One run per automation per check, however many of its schedules came due, and a time that passed
/// long ago (Native wasn't running) runs once, marked missed, never as a backlog.
nonisolated enum AutomationPlanner {
    /// A due time older than this ran late because Native wasn't running, not because of a slow tick.
    static let missedAfter: TimeInterval = 15 * 60

    static func due(_ automations: [Automation], lastChecked: [Automation.ID: Date], now: Date) -> [(Automation.ID, AutomationRunReason)] {
        automations.compactMap { automation in
            let since = lastChecked[automation.id] ?? automation.createdAt
            guard let next = automation.nextFire(after: since), next <= now else { return nil }
            return (automation.id, now.timeIntervalSince(next) > missedAfter ? .missed(next) : .scheduled(next))
        }
    }

    /// When the next scheduled run is, across every automation, to sleep until then.
    static func nextWake(_ automations: [Automation], lastChecked: [Automation.ID: Date], now: Date) -> Date? {
        automations.compactMap { $0.nextFire(after: lastChecked[$0.id] ?? $0.createdAt) }.map { max($0, now) }.min()
    }
}
