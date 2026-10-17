import Foundation

/// When a scheduled automation runs. Times are wall-clock times in the user's calendar, so "9:00 AM"
/// stays 9:00 AM across daylight saving changes.
nonisolated enum AutomationSchedule: Codable, Hashable, Sendable {
    case daily(hour: Int, minute: Int)
    /// `weekday` as `Calendar` counts it: 1 is Sunday.
    case weekly(weekday: Int, hour: Int, minute: Int)
    case everyHours(Int)

    /// The first time after `date` it fires. Interval schedules count from `anchor` (when the
    /// automation was made), so "every 4 hours" keeps a steady rhythm instead of drifting with
    /// late runs.
    func nextFire(after date: Date, anchor: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .daily(let hour, let minute):
            return calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: minute), matchingPolicy: .nextTime) ?? date.addingTimeInterval(86_400)
        case .weekly(let weekday, let hour, let minute):
            let components = DateComponents(hour: hour, minute: minute, weekday: weekday)
            return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTime) ?? date.addingTimeInterval(7 * 86_400)
        case .everyHours(let hours):
            let interval = TimeInterval(max(hours, 1) * 3600)
            guard date >= anchor else { return anchor }
            let elapsed = date.timeIntervalSince(anchor)
            return anchor.addingTimeInterval((elapsed / interval).rounded(.down) * interval + interval)
        }
    }

    /// "Every day at 9:00 AM", "Mondays at 9:00 AM", "Every 4 hours".
    func summary(calendar: Calendar = .current) -> String {
        switch self {
        case .daily(let hour, let minute):
            return "Every day at \(Self.time(hour: hour, minute: minute, calendar: calendar))"
        case .weekly(let weekday, let hour, let minute):
            let names = calendar.standaloneWeekdaySymbols
            let name = names.indices.contains(weekday - 1) ? names[weekday - 1] : "Weekly"
            return "\(name)s at \(Self.time(hour: hour, minute: minute, calendar: calendar))"
        case .everyHours(let hours):
            return hours == 1 ? "Every hour" : "Every \(hours) hours"
        }
    }

    private static func time(hour: Int, minute: Int, calendar: Calendar) -> String {
        let date = calendar.date(from: DateComponents(hour: hour, minute: minute)) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }
}
