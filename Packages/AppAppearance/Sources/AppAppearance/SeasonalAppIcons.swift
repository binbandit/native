import Foundation

/// Seasonal dates use the local Gregorian calendar, independently of the user's display calendar.
public enum SeasonalAppIcons {
    public static func halloweenIsAvailable(on date: Date, timeZone: TimeZone = .current) -> Bool {
        let parts = calendar(in: timeZone).dateComponents([.month, .day], from: date)
        return parts.month == 10 || (parts.month == 11 && (parts.day ?? 0) <= 7)
    }

    /// The next opening or closing boundary, including daylight-saving and time-zone changes.
    public static func nextHalloweenBoundary(after date: Date, timeZone: TimeZone = .current) -> Date? {
        let isAvailable = halloweenIsAvailable(on: date, timeZone: timeZone)
        return calendar(in: timeZone).nextDate(
            after: date,
            matching: DateComponents(
                month: isAvailable ? 11 : 10, day: isAvailable ? 8 : 1, hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
