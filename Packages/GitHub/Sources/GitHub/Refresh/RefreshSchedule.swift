import Foundation

/// When to refresh pull requests next. A steady interval while things work, and backing off on
/// failure, so a laptop that's offline or over its rate limit doesn't keep spawning gh. Each inbox
/// refresh spends three of GitHub's 30 searches a minute, so even the fastest interval is cheap.
public struct RefreshSchedule: Sendable, Hashable {
    public enum Activity: Sendable, Hashable {
        /// Someone is looking at pull requests: refresh often.
        case watching
        /// Only badges and counts depend on it.
        case background
    }

    public var watchingInterval: TimeInterval = 120
    public var backgroundInterval: TimeInterval = 600
    public var firstRetry: TimeInterval = 30
    public var longestRetry: TimeInterval = 900
    /// How old results must be before coming back to the app refreshes them.
    public var returnThreshold: TimeInterval = 60

    public private(set) var lastAttempt: Date?
    public private(set) var lastSuccess: Date?
    public private(set) var consecutiveFailures = 0
    public private(set) var lastFailure: GitHubError?
    /// Set while rate limited: nothing is sent before it.
    public private(set) var notBefore: Date?

    public init() {}

    public mutating func recordSuccess(at date: Date) {
        lastAttempt = date
        lastSuccess = date
        consecutiveFailures = 0
        lastFailure = nil
        notBefore = nil
    }

    /// - Parameter rateLimitResetsAt: When the exhausted budget refills, if known.
    public mutating func recordFailure(_ error: GitHubError, at date: Date, rateLimitResetsAt: Date? = nil) {
        lastAttempt = date
        consecutiveFailures += 1
        lastFailure = error
        // A few seconds past the reset, since GitHub's clock and ours differ slightly.
        notBefore = if case .rateLimited = error { rateLimitResetsAt.map { $0.addingTimeInterval(5) } } else { nil }
    }

    /// When the next refresh is due; the distant past before the first one.
    public func nextRefresh(_ activity: Activity) -> Date {
        guard let lastAttempt else { return .distantPast }
        guard let lastFailure else {
            return lastAttempt.addingTimeInterval(activity == .watching ? watchingInterval : backgroundInterval)
        }
        if let notBefore {
            return notBefore
        }
        // Signing in or installing gh happens outside Native; coming back to the app or Retry
        // picks that up sooner.
        guard lastFailure.isTransient else {
            return lastAttempt.addingTimeInterval(backgroundInterval)
        }
        let exponent = Double(min(consecutiveFailures - 1, 16))
        return lastAttempt.addingTimeInterval(min(firstRetry * pow(2, exponent), longestRetry))
    }

    public func isDue(_ activity: Activity, at now: Date) -> Bool {
        nextRefresh(activity) <= now
    }

    /// Whether returning to the app should refresh right away: results are old enough, or the
    /// last attempt failed in a way the user may have fixed meanwhile (never while rate limited).
    public func refreshesOnReturn(at now: Date) -> Bool {
        if let notBefore, now < notBefore { return false }
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= returnThreshold
    }
}
