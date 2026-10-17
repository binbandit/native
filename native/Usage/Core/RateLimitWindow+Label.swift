import ACP
import Foundation

extension RateLimitInfo.Window {
    /// The window as `LimitStatus` names it, without "limit": "5-hour", "weekly", "weekly Opus".
    var label: String {
        switch self {
        case .fiveHour: "5-hour"
        case .sevenDay, .sevenDayOverageIncluded: "weekly"
        case .sevenDayOpus: "weekly Opus"
        case .sevenDaySonnet: "weekly Sonnet"
        case .overage: "usage credit"
        case .other(let name): name.replacingOccurrences(of: "_", with: " ")
        }
    }
}

extension ProviderLimit {
    /// The limit as every surface shows it, with what it means for one session's work.
    func limitStatus(resume: LimitStatus.Resume = .notNeeded) -> LimitStatus {
        LimitStatus(
            id: agent.rawValue,
            provider: agentName,
            level: status == .reached ? .reached : .warning,
            window: window?.label,
            resetsAt: resetsAt,
            utilization: utilization,
            message: message,
            isSnoozed: isSnoozed,
            resume: resume
        )
    }
}
