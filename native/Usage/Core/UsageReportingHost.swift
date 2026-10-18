import ACP
import Foundation

/// What Settings › Usage needs from the app. `AppModel` conforms.
protocol UsageReportingHost: AnyObject {
    /// An open, idle task of the agent to run its status command in; nil when there's none.
    func reportingSession(for agent: AgentDefinition.ID) -> (any ContextReporting)?
    /// The agent's open tasks with what they've used so far, the most expensive first.
    func taskUsage(of agent: AgentDefinition.ID) -> [UsageTaskSpend]
}

/// Everything Usage needs from the app.
typealias UsageHost = UsageLimitsHost & UsageNotificationsHost & UsageReportingHost

/// What one task has used, as its agent reports it.
struct UsageTaskSpend: Hashable, Identifiable {
    let id: SessionID
    let title: String
    let contextUsed: Int
    let contextSize: Int
    let cost: Usage.Cost?
}
