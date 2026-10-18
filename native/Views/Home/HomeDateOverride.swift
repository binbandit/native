import Foundation

/// A development clock for checking seasonal looks (the Halloween icons and landing page) on any
/// day: launch with `-nativeDate 2026-10-31` and the app's season logic runs as if it were that day,
/// with time moving on from launch. Without the argument it's the real clock.
nonisolated enum HomeDateOverride {
    /// The current date, shifted to the launch argument's day when there is one.
    static func now() -> Date {
        Date.now.addingTimeInterval(offset)
    }

    /// Noon on the requested day, local time, minus the launch time; noon keeps the day the same
    /// across time-zone changes.
    private static let offset: TimeInterval = {
        guard let day = UserDefaults.standard.string(forKey: "nativeDate"),
            let date = try? Date.ISO8601FormatStyle(timeZone: .current).year().month().day().parse(day),
            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date)
        else { return 0 }
        return noon.timeIntervalSinceNow
    }()
}
