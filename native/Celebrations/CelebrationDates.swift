import AppAppearance
import Foundation

/// Celebration days in the user's language and date format. Locale shapes how dates read, never
/// which celebrations are offered.
enum CelebrationDates {
    /// "1 Oct – 7 Nov 2026", or "31 Oct 2026" for one day.
    static func text(_ range: CivilDayRange, in timeZone: TimeZone = .current) -> String {
        let first = noon(range.first, in: timeZone)
        guard range.first != range.last else {
            return first.formatted(.dateTime.day().month(.abbreviated).year())
        }
        return (first..<noon(range.last, in: timeZone)).formatted(
            .interval.day().month(.abbreviated).year())
    }

    /// "31 Oct" without the year, for a range already dated.
    static func shortText(_ range: CivilDayRange, in timeZone: TimeZone = .current) -> String {
        let first = noon(range.first, in: timeZone)
        guard range.first != range.last else { return first.formatted(.dateTime.day().month(.abbreviated)) }
        return (first..<noon(range.last, in: timeZone)).formatted(.interval.day().month(.abbreviated))
    }

    /// Noon keeps a day's date stable whatever the time zone does at midnight.
    private static func noon(_ day: CivilDate, in timeZone: TimeZone) -> Date {
        day.start(in: timeZone).addingTimeInterval(12 * 60 * 60)
    }
}
