import Foundation

/// A day on the proleptic Gregorian calendar, with no time of day and no time zone: "1 November
/// 2026" wherever the user is. Celebrations are reckoned in these, so a display window is a count of
/// calendar days and never a multiple of 86,400 seconds, and a daylight-saving change can't move a
/// boundary onto the wrong day.
public struct CivilDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), (1...Self.daysIn(month: month, year: year)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local date of `date` in `timeZone`, independently of the user's display calendar.
    public init(_ date: Date, in timeZone: TimeZone) {
        let parts = Self.calendar(in: timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(unchecked: parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Parses "2026-11-01".
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// Days since 1970-01-01 (negative before it), from Howard Hinnant's `days_from_civil`.
    public var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The inverse of `dayNumber` (Hinnant's `civil_from_days`).
    public init(dayNumber: Int) {
        let z = dayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let mp = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        self.init(unchecked: yearOfEra + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    public func adding(days: Int) -> CivilDate {
        CivilDate(dayNumber: dayNumber + days)
    }

    /// The first instant of this day in `timeZone`. Where a daylight-saving change skips midnight
    /// (Havana, Beirut), that's the first time the day has, such as 01:00.
    public func start(in timeZone: TimeZone) -> Date {
        let calendar = Self.calendar(in: timeZone)
        // Noon always exists, so it pins the day before asking for its start.
        let noon = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
        return calendar.startOfDay(for: noon)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func isLeap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    public static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: isLeap(year) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// For dates computed to be valid (Easter) or written into Native's catalogue.
    init(literal year: Int, _ month: Int, _ day: Int) {
        self.init(unchecked: year, month, day)
    }

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}

extension CivilDate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = CivilDate(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" isn't a date like \"2026-11-01\".")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// Consecutive days, both ends included: "1 October through 7 November".
public struct CivilDayRange: Hashable, Sendable {
    public let first: CivilDate
    public let last: CivilDate

    /// Nil when `last` comes before `first`.
    public init?(first: CivilDate, last: CivilDate) {
        guard first <= last else { return nil }
        self.first = first
        self.last = last
    }

    public init(day: CivilDate) {
        first = day
        last = day
    }

    public func contains(_ day: CivilDate) -> Bool {
        first <= day && day <= last
    }

    public func overlaps(_ other: CivilDayRange) -> Bool {
        first <= other.last && other.first <= last
    }

    public var dayCount: Int { last.dayNumber - first.dayNumber + 1 }

    /// The range grown by whole days at each end.
    public func expanded(before: Int, after: Int) -> CivilDayRange {
        CivilDayRange(unchecked: first.adding(days: -before), last.adding(days: after))
    }

    private init(unchecked first: CivilDate, _ last: CivilDate) {
        self.first = first
        self.last = last
    }
}

/// A month and day with no year, as in a manifest's "10-31". Valid if the day exists in some year, so
/// "02-29" is allowed and simply has no occurrence in common years.
public struct MonthDay: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let month: Int
    public let day: Int

    public init?(month: Int, day: Int) {
        guard (1...12).contains(month), (1...CivilDate.daysIn(month: month, year: 2000)).contains(day) else {
            return nil
        }
        self.month = month
        self.day = day
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ $0.count == 2 }), let month = Int(parts[0]), let day = Int(parts[1])
        else { return nil }
        self.init(month: month, day: day)
    }

    /// For literals in Native's own catalogue, which the tests check resolve.
    init(literal month: Int, _ day: Int) {
        self.month = month
        self.day = day
    }

    /// This day in `year`, or nil for 29 February in a common year.
    public func date(in year: Int) -> CivilDate? {
        CivilDate(year: year, month: month, day: day)
    }

    public var description: String {
        String(format: "%02d-%02d", month, day)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.month, lhs.day) < (rhs.month, rhs.day)
    }
}

extension MonthDay: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let value = MonthDay(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "\"\(text)\" isn't a month and day like \"10-31\".")
        }
        self = value
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
