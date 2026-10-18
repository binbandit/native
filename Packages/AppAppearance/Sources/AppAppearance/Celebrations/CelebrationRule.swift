/// How a celebration's core observance falls in the year. Every resolver produces the same thing,
/// core day ranges for a queried span, so display windows, overlap and scheduling work alike for
/// every calendar.
///
/// Rules: fixed civil dates, nth weekdays of a month, a day of the year, Western Easter and Orthodox
/// Pascha (each with an offset, for days like Mardi Gras), and published annual tables for calendars
/// without a verified rule here (lunisolar, Hebrew, Islamic). Any other `kind` decodes as
/// `unsupported`: listed as coming soon and never applied.
public enum CelebrationRule: Hashable, Sendable {
    /// The same civil dates every year: one day, or a range that may cross into the next year
    /// (26 December through 1 January). A date that doesn't exist in a year (29 February) has no
    /// occurrence that year.
    case fixed(start: MonthDay, end: MonthDay)
    /// The `ordinal`th `weekday` of `month` (1 = Sunday … 7 = Saturday; ordinal -1 is the last), for
    /// `length` days: US Thanksgiving is the 4th Thursday of November.
    case nthWeekday(month: Int, weekday: Int, ordinal: Int, length: Int)
    /// The `day`th day of the year (Programmers' Day is 256: 13 September, or 12 in leap years).
    case dayOfYear(day: Int, length: Int)
    /// Days from an Easter Sunday: 0 is Easter itself, -47 Mardi Gras.
    case easter(Computus, offset: Int, length: Int)
    /// Published occurrences, for calendars resolved from an authority's annual dates.
    case table([CivilDayRange])
    /// A calendar this version can't resolve, by its manifest `kind`.
    case unsupported(kind: String)

    /// Which Easter.
    public enum Computus: String, Hashable, Sendable {
        /// The Gregorian computus of the Western churches.
        case western = "western-easter"
        /// The Julian computus of the Orthodox churches, given as a Gregorian date.
        case orthodox = "orthodox-pascha"
    }

    public var isResolvable: Bool {
        if case .unsupported = self { return false }
        return true
    }

    /// The core observances that overlap `span`, earliest first; nil when the rule can't be resolved.
    public func coreRanges(overlapping span: CivilDayRange) -> [CivilDayRange]? {
        let years = span.first.year - 1...span.last.year
        let ranges: [CivilDayRange]
        switch self {
        case .fixed(let start, let end):
            let crossesYear = end < start
            ranges = years.compactMap { year in
                guard let first = start.date(in: year), let last = end.date(in: crossesYear ? year + 1 : year) else {
                    return nil
                }
                return CivilDayRange(first: first, last: last)
            }
        case .nthWeekday(let month, let weekday, let ordinal, let length):
            ranges = years.compactMap {
                Self.nthWeekday(ordinal, weekday, of: month, in: $0).map { Self.days($0, length) }
            }
        case .dayOfYear(let day, let length):
            ranges = years.compactMap { year in
                guard let january = CivilDate(year: year, month: 1, day: 1) else { return nil }
                let date = january.adding(days: day - 1)
                return date.year == year ? Self.days(date, length) : nil
            }
        case .easter(let computus, let offset, let length):
            ranges = years.map { Self.days(Self.easter(computus, in: $0).adding(days: offset), length) }
        case .table(let occurrences):
            ranges = occurrences.sorted { $0.first < $1.first }
        case .unsupported:
            return nil
        }
        return ranges.filter { $0.overlaps(span) }
    }

    /// The last year a table covers, for saying its dates have run out.
    var lastTabledYear: Int? {
        guard case .table(let occurrences) = self else { return nil }
        return occurrences.map(\.first.year).max()
    }

    // MARK: - Resolvers

    private static func days(_ first: CivilDate, _ length: Int) -> CivilDayRange {
        CivilDayRange(day: first).expanded(before: 0, after: max(length, 1) - 1)
    }

    /// 1 = Sunday … 7 = Saturday. 1970-01-01 was a Thursday.
    static func weekday(of date: CivilDate) -> Int {
        ((date.dayNumber % 7 + 7) % 7 + 4) % 7 + 1
    }

    static func nthWeekday(_ ordinal: Int, _ weekday: Int, of month: Int, in year: Int) -> CivilDate? {
        guard (1...7).contains(weekday), ordinal != 0 else { return nil }
        if ordinal > 0 {
            guard let first = CivilDate(year: year, month: month, day: 1) else { return nil }
            let date = first.adding(days: (weekday - Self.weekday(of: first) + 7) % 7 + (ordinal - 1) * 7)
            return date.month == month ? date : nil
        }
        guard let last = CivilDate(year: year, month: month, day: CivilDate.daysIn(month: month, year: year)) else {
            return nil
        }
        let date = last.adding(days: -((Self.weekday(of: last) - weekday + 7) % 7) + (ordinal + 1) * 7)
        return date.month == month ? date : nil
    }

    /// Easter Sunday as a Gregorian date: the anonymous Gregorian algorithm (Meeus, Jones, Butcher)
    /// for the West, and Meeus's Julian algorithm shifted to the Gregorian calendar for Pascha.
    static func easter(_ computus: Computus, in year: Int) -> CivilDate {
        switch computus {
        case .western:
            let a = year % 19
            let b = year / 100
            let c = year % 100
            let d = b / 4
            let e = b % 4
            let f = (b + 8) / 25
            let g = (b - f + 1) / 3
            let h = (19 * a + b - d - g + 15) % 30
            let i = c / 4
            let k = c % 4
            let l = (32 + 2 * e + 2 * i - h - k) % 7
            let m = (a + 11 * h + 22 * l) / 451
            let month = (h + l - 7 * m + 114) / 31
            let day = (h + l - 7 * m + 114) % 31 + 1
            return CivilDate(literal: year, month, day)
        case .orthodox:
            let a = year % 4
            let b = year % 7
            let c = year % 19
            let d = (19 * c + 15) % 30
            let e = (2 * a + 4 * b - d + 34) % 7
            let month = (d + e + 114) / 31
            let day = (d + e + 114) % 31 + 1
            // Julian to Gregorian: 13 days in 1900–2099; Pascha always falls after any century's
            // leap-day difference has taken effect.
            let difference = year / 100 - year / 400 - 2
            return CivilDate(literal: year, month, day).adding(days: difference)
        }
    }
}
