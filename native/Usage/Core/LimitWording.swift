import ACP
import Foundation

/// The one way Native words a usage limit, so the banner, notifications, status bar and sidebar
/// say exactly the same thing: which provider, which window, how much is used when that's known,
/// and when it resets ("Claude Code · 5-hour limit reached · resets 3:05 PM, in 42 min").
enum LimitWording {
    static func limitName(_ window: RateLimitInfo.Window?) -> String {
        switch window {
        case .fiveHour?: "5-hour limit"
        case .sevenDay?, .sevenDayOverageIncluded?: "weekly limit"
        case .sevenDayOpus?: "weekly Opus limit"
        case .sevenDaySonnet?: "weekly Sonnet limit"
        case .overage?: "usage credit limit"
        case .other(let name)?: name.replacingOccurrences(of: "_", with: " ") + " limit"
        case nil: "usage limit"
        }
    }

    /// "Claude Code · 5-hour limit reached", "Claude Code · 5-hour limit 90% used"
    static func headline(agentName: String, window: RateLimitInfo.Window?, status: ProviderLimit.Status, utilization: Double?) -> String {
        let name = limitName(window)
        switch status {
        case .reached:
            return "\(agentName) · \(name) reached"
        case .warning:
            guard let utilization else { return "\(agentName) · \(name) almost reached" }
            return "\(agentName) · \(name) \(TokenFormat.percent(utilization)) used"
        }
    }

    /// "resets 3:05 PM, in 42 min"
    static func reset(_ date: Date, now: Date) -> String {
        "resets \(ResetTimeFormat.timeAndCountdown(date, now: now))"
    }

    /// "resumes 3:07 PM, in 44 min"
    static func resume(_ date: Date, now: Date) -> String {
        "resumes \(ResetTimeFormat.timeAndCountdown(date, now: now))"
    }

    /// The headline and, when known, the reset: the whole sentence for one-line places.
    static func line(_ limit: ProviderLimit, now: Date) -> String {
        [limit.headline, limit.resetsAt.map { reset($0, now: now) }].compactMap(\.self).joined(separator: " · ")
    }

    static func availableAgain(agentName: String, window: RateLimitInfo.Window?) -> String {
        "\(agentName) · \(limitName(window)) reset"
    }
}

extension ProviderLimit {
    var limitName: String {
        LimitWording.limitName(window)
    }

    var headline: String {
        LimitWording.headline(agentName: agentName, window: window, status: status, utilization: utilization)
    }
}
