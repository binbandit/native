/// How a celebration's core observance falls in the year. Each resolver produces the same thing,
/// core day ranges for a queried span, so display windows, overlap and scheduling work alike for
/// every calendar.
///
/// Only fixed civil dates resolve today. Other kinds (`western-easter`, `orthodox-pascha`, `hebrew`,
/// `islamic`, `chinese-lunisolar`, `table`, ...) decode as `unsupported`: the catalogue lists them
/// and says their dates can't be worked out yet, and a later resolver is a new case here plus its
/// branch in `coreRanges`, with no change to the manifest format.
public enum CelebrationRule: Hashable, Sendable {
    /// The same civil dates every year: one day, or a range that may cross into the next year
    /// (26 December through 1 January). A date that doesn't exist in a year (29 February) has no
    /// occurrence that year.
    case fixed(start: MonthDay, end: MonthDay)
    /// A calendar this version can't resolve, by its manifest `kind`.
    case unsupported(kind: String)

    static let fixedKind = "fixed"

    public var isResolvable: Bool {
        if case .unsupported = self { return false }
        return true
    }

    /// The core observances that overlap `span`, earliest first; nil when the rule can't be resolved.
    public func coreRanges(overlapping span: CivilDayRange) -> [CivilDayRange]? {
        switch self {
        case .fixed(let start, let end):
            let crossesYear = end < start
            // A range that starts the year before can still reach into the span.
            return (span.first.year - 1...span.last.year).compactMap { year in
                guard let first = start.date(in: year), let last = end.date(in: crossesYear ? year + 1 : year),
                    let range = CivilDayRange(first: first, last: last), range.overlaps(span)
                else { return nil }
                return range
            }
        case .unsupported:
            return nil
        }
    }
}
