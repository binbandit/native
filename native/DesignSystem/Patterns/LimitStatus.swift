import Foundation

/// Where one provider (an agent's account) stands against a usage limit, as every surface shows
/// it. Usage produces these; `LimitBanner` and `LimitChip` render them, and `LimitStatus` words
/// them, so the banner, notifications, status bar and sidebar all say the same thing.
public nonisolated struct LimitStatus: Hashable, Sendable, Identifiable {
    public enum Level: Hashable, Sendable {
        /// Close to the limit; requests still go through.
        case warning
        /// Requests are refused until the reset.
        case reached
    }

    /// Whether a session stopped by the limit can pick back up on its own.
    public enum Resume: Hashable, Sendable {
        /// Nothing was interrupted.
        case notNeeded
        /// The provider gave no reset time, so nothing can be scheduled.
        case unavailable
        /// A resume at the reset can be scheduled.
        case offered
        /// The session resumes then.
        case scheduled(Date)
    }

    public var id: String
    /// The agent's display name, e.g. "Claude Code".
    public var provider: String
    public var level: Level
    /// The window's label without "limit": "5-hour", "weekly", "weekly Opus". Nil when unknown.
    public var window: String?
    public var resetsAt: Date?
    /// Used share of the window, 0...1, when the provider reports it.
    public var utilization: Double?
    /// The provider's own words, for limits Native can't name.
    public var message: String?
    /// The user asked for quiet until the reset.
    public var isSnoozed: Bool
    public var resume: Resume

    public init(
        id: String,
        provider: String,
        level: Level,
        window: String? = nil,
        resetsAt: Date? = nil,
        utilization: Double? = nil,
        message: String? = nil,
        isSnoozed: Bool = false,
        resume: Resume = .notNeeded
    ) {
        self.id = id
        self.provider = provider
        self.level = level
        self.window = window
        self.resetsAt = resetsAt
        self.utilization = utilization
        self.message = message
        self.isSnoozed = isSnoozed
        self.resume = resume
    }
}

// MARK: - Wording

extension LimitStatus {
    /// "5-hour limit", "weekly Opus limit", "usage limit".
    public var limitName: String {
        window.map { "\($0) limit" } ?? "usage limit"
    }

    /// "Claude Code · 5-hour limit reached", "Claude Code · 5-hour limit 90% used".
    public var headline: String {
        switch level {
        case .reached:
            "\(provider) · \(limitName) reached"
        case .warning:
            utilization.map { "\(provider) · \(limitName) \(DSFormat.percent($0)) used" }
                ?? "\(provider) · \(limitName) almost reached"
        }
    }

    /// "resets 3:05 PM, in 42 min"; nil without a reset time.
    public func resetText(now: Date) -> String? {
        resetsAt.map { "resets \(DSFormat.timeAndCountdown($0, now: now))" }
    }

    /// The whole sentence for one-line places and notifications:
    /// "Claude Code · 5-hour limit reached · resets 3:05 PM, in 42 min".
    public func line(now: Date) -> String {
        [headline, resetText(now: now)].compactMap(\.self).joined(separator: " · ")
    }

    /// What happens to interrupted work: "Resumes 3:07 PM, in 44 min".
    public func resumeText(now: Date) -> String? {
        switch resume {
        case .notNeeded, .offered: nil
        case .unavailable: "No reset time given, so it can't resume on its own"
        case .scheduled(let date): "Resumes \(DSFormat.timeAndCountdown(date, now: now))"
        }
    }

    /// The compact form for chips: "5-hour limit · 42 min", "weekly 90%".
    public func compactText(now: Date) -> String {
        switch level {
        case .reached:
            let countdown =
                resetsAt
                .flatMap { DSFormat.countdown(to: $0, now: now) }
                .map { $0.replacingOccurrences(of: "in ", with: "") }
            return [limitName, countdown].compactMap(\.self).joined(separator: " · ")
        case .warning:
            return [window ?? "Usage", utilization.map(DSFormat.percent)].compactMap(\.self).joined(separator: " ")
        }
    }

    /// "Available again: Claude Code · 5-hour limit reset".
    public var availableAgainText: String {
        "\(provider) · \(limitName) reset"
    }
}
