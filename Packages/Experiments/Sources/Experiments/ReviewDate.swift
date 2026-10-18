import Foundation

/// The day an experiment should be promoted to a default, kept as a setting, or deleted. Labs
/// flags experiments past it, so none linger.
public struct ReviewDate: Hashable, Sendable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Reads `YYYY-MM-DD`, as plugin manifests write it.
    public init?(iso text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// Midnight at the start of the day, in `calendar`'s time zone.
    public func date(in calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Whether the review day has started by `now`.
    public func isDue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let date = date(in: calendar) else { return false }
        return now >= date
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
