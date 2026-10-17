import ACP
import Foundation

/// What a session's limit banner shows: the provider's limit as it applies to that session.
struct LimitNotice: Hashable {
    enum Kind: Hashable {
        case warning
        case reached
        /// Reached, and the user asked for quiet until the reset.
        case snoozed
    }

    enum Resume: Hashable {
        /// The limit didn't stop this session, so there's nothing to resume.
        case notNeeded
        /// The reset time is unknown, so nothing can be scheduled.
        case unavailable
        case offered
        case scheduled(Date, prompt: String)
    }

    let limit: ProviderLimit
    let kind: Kind
    let resume: Resume

    /// The banner's second part: when the session resumes, or else when the limit resets.
    func detail(now: Date) -> String? {
        if case .scheduled(let date, _) = resume {
            return LimitWording.resume(date, now: now)
        }
        if let resetsAt = limit.resetsAt {
            return LimitWording.reset(resetsAt, now: now)
        }
        // Without a reset time, the provider's own words are the most exact thing there is.
        return limit.message
    }
}
