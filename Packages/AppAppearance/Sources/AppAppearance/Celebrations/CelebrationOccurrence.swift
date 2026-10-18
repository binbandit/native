/// One time a celebration happens: its core observance and the display window around it in effect.
/// An event can occur more than once in a Gregorian year (a window that crosses New Year), or not at
/// all (29 February), so occurrences are always queried for a span, never assumed per year.
public struct CelebrationOccurrence: Hashable, Sendable, Identifiable {
    /// The event and the first core day: `native.halloween@2026-10-31`. Skips are stored by it, so a
    /// skip covers this year's occurrence and never next year's.
    public struct ID: Hashable, Sendable, Codable, CustomStringConvertible {
        public let eventID: CelebrationID
        public let coreStart: CivilDate

        public init(eventID: CelebrationID, coreStart: CivilDate) {
            self.eventID = eventID
            self.coreStart = coreStart
        }

        public init?(_ text: String) {
            guard let separator = text.lastIndex(of: "@"),
                let start = CivilDate(String(text[text.index(after: separator)...]))
            else { return nil }
            self.init(eventID: CelebrationID(String(text[..<separator])), coreStart: start)
        }

        public var description: String { "\(eventID)@\(coreStart)" }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let id = ID(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad occurrence \"\(text)\".")
            }
            self = id
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(description)
        }
    }

    /// Core observance days outrank another celebration's decorative days.
    public enum Tier: Int, Comparable, Sendable {
        case decorative
        case core

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let eventID: CelebrationID
    public let core: CivilDayRange
    /// The days it shows: the core dates, or a chosen window around them.
    public let display: CivilDayRange

    public init(eventID: CelebrationID, core: CivilDayRange, display: CivilDayRange) {
        self.eventID = eventID
        self.core = core
        self.display = display
    }

    public var id: ID { ID(eventID: eventID, coreStart: core.first) }

    /// How `day` counts for this occurrence, or nil outside its display window.
    public func tier(on day: CivilDate) -> Tier? {
        if core.contains(day) { return .core }
        return display.contains(day) ? .decorative : nil
    }

    /// The days where the outcome can change: the starts and day-afters of both ranges.
    var edges: [CivilDate] {
        [display.first, core.first, core.last.adding(days: 1), display.last.adding(days: 1)]
    }
}
