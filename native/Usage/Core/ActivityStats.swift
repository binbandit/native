import Foundation

/// The quiet game: streaks, the busiest day, and the year's total, for one metric.
struct ActivityStats: Hashable {
    let currentStreak: Int
    let longestStreak: Int
    let busiest: (day: Date, value: Double)?
    let total: Double
    let activeDays: Int

    /// `values` by local day start. A streak still counts today if it reached yesterday, so the day
    /// isn't lost before the user has started.
    init(values: [Date: Double], today: Date, calendar: Calendar) {
        let active = Set(values.filter { $0.value > 0 }.keys)
        total = values.values.reduce(0, +)
        activeDays = active.count
        busiest = values.filter { $0.value > 0 }.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }

        let start = calendar.startOfDay(for: today)
        var day = active.contains(start) ? start : calendar.date(byAdding: .day, value: -1, to: start) ?? start
        var current = 0
        while active.contains(day) {
            current += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        currentStreak = current

        var longest = 0
        var run = 0
        var previous: Date?
        for day in active.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        longestStreak = longest
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.currentStreak == rhs.currentStreak && lhs.longestStreak == rhs.longestStreak && lhs.total == rhs.total
            && lhs.activeDays == rhs.activeDays && lhs.busiest?.day == rhs.busiest?.day
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(currentStreak)
        hasher.combine(longestStreak)
        hasher.combine(total)
    }
}
