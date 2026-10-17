import ACP
import Foundation

/// Where one provider (an agent) stands against its usage limit. Limits belong to the account
/// behind the agent, so every session of the agent shares this.
struct ProviderLimit: Codable, Hashable, Identifiable {
    enum Status: String, Codable {
        /// Close to the limit; requests still go through.
        case warning
        /// Requests are refused until `resetsAt`.
        case reached
    }

    let agent: AgentDefinition.ID
    var agentName: String
    var status: Status
    var window: RateLimitInfo.Window?
    /// Nil when the provider didn't say; nothing can be scheduled then.
    var resetsAt: Date?
    /// Used share of the window, 0-1.
    var utilization: Double?
    /// The provider's own words, for limits Native can't name.
    var message: String?
    var updatedAt: Date
    /// The user asked for quiet until the reset, and one notification when it comes.
    var isSnoozed = false
    var isDismissed = false
    /// Set once this incident has been notified, so repeats of the same status stay quiet.
    var hasAlerted = false

    var id: AgentDefinition.ID { agent }
}
