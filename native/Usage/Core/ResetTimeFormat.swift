import Foundation

/// The one way Native words a time to come: "3:05 PM", "tomorrow at 9:00 AM", "Mon, Oct 20 at
/// 3:00 PM", and how far off it is ("in 42 min").
enum ResetTimeFormat {
    static func time(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return clock
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(clock)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(clock)"
    }

    /// "in 42 min", "in 2 hr 14 min", "in 3 days"; nil once the time has passed.
    static func countdown(to date: Date, now: Date) -> String? {
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let minutes = Int((seconds / 60).rounded(.up))
        if seconds < 60 { return "in under a minute" }
        if minutes < 60 { return "in \(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "in \(hours) hr" : "in \(hours) hr \(minutes % 60) min" }
        let days = hours / 24
        let dayText = days == 1 ? "1 day" : "\(days) days"
        return hours % 24 == 0 ? "in \(dayText)" : "in \(dayText) \(hours % 24) hr"
    }

    /// "3:05 PM, in 42 min"
    static func timeAndCountdown(_ date: Date, now: Date) -> String {
        [time(date, now: now), countdown(to: date, now: now)].compactMap(\.self).joined(separator: ", ")
    }
}
