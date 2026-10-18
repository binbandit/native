import Foundation

/// A contribution that passed validation, with its artwork checked and resolved: what the catalogue
/// lists and the policy chooses from.
public struct CelebrationEvent: Hashable, Sendable, Identifiable {
    /// Whether one surface of an edition can be applied.
    public enum SurfaceStatus: Hashable, Sendable {
        case ready
        /// The contribution doesn't change this surface.
        case notOffered
        /// Planned; the catalogue says the artwork is on its way.
        case forthcoming
        /// Declared but unusable, such as missing icon files; the reason is for the catalogue.
        case unavailable(String)

        public var isReady: Bool { self == .ready }
    }

    /// Whether Native can work out the event's dates.
    public enum DateStatus: Hashable, Sendable {
        case resolvable
        /// A calendar this version doesn't resolve yet, by its manifest kind.
        case unsupportedCalendar(String)
        /// An annual table that ends before the day asked about.
        case coverageEnded(lastYear: Int)
    }

    public let contribution: CelebrationContribution
    public let pluginID: String
    /// Position in the catalogue: the overlap order until the user sets their own.
    public let order: Int
    public let appIcon: SurfaceStatus
    public let home: SurfaceStatus
    /// Each channel's light and dark icons, when `appIcon` is ready.
    public let icons: [AppIconVariant: AppIconImagePair]

    public init(
        contribution: CelebrationContribution, pluginID: String, order: Int, appIcon: SurfaceStatus,
        home: SurfaceStatus, icons: [AppIconVariant: AppIconImagePair] = [:]
    ) {
        self.contribution = contribution
        self.pluginID = pluginID
        self.order = order
        self.appIcon = appIcon
        self.home = home
        self.icons = icons
    }

    public var id: CelebrationID { contribution.id }
    public var display: CelebrationDisplay { contribution.display }

    /// The design-system mark Home draws, when that surface is ready.
    public var homeMark: String? {
        guard home.isReady, case .mark(let mark) = contribution.artwork.home else { return nil }
        return mark
    }

    public func icon(for variant: AppIconVariant, isDark: Bool) -> AppIconImage? {
        icons[variant]?.image(isDark: isDark)
    }

    /// Whether anything is ready to apply: an edition with neither surface can be browsed, not used.
    public var isApplicable: Bool { appIcon.isReady || home.isReady }

    public func dateStatus(on day: CivilDate) -> DateStatus {
        if case .unsupported(let kind) = contribution.calendar.rule { return .unsupportedCalendar(kind) }
        if let coverage = contribution.provenance.coverage, day.year > coverage.through {
            return .coverageEnded(lastYear: coverage.through)
        }
        return .resolvable
    }

    /// Occurrences whose display window, in the chosen `window`, overlaps `span`. Empty when the
    /// dates can't be resolved, which leaves the base appearance in place.
    public func occurrences(window: CelebrationWindow.ID?, overlapping span: CivilDayRange) -> [CelebrationOccurrence] {
        let window = display.window(window)
        // Widen the search so a core date just outside the span whose window reaches into it is found.
        let search = span.expanded(before: window.daysAfter, after: window.daysBefore)
        let coverage = contribution.provenance.coverage
        return (contribution.calendar.rule.coreRanges(overlapping: search) ?? [])
            .filter { core in coverage.map { ($0.from...$0.through).contains(core.first.year) } ?? true }
            .map {
                CelebrationOccurrence(
                    eventID: id, core: $0, display: $0.expanded(before: window.daysBefore, after: window.daysAfter))
            }
            .filter { $0.display.overlaps(span) }
    }

    /// The occurrence showing on `day`, or the next one after it.
    public func nextOccurrence(window: CelebrationWindow.ID?, from day: CivilDate) -> CelebrationOccurrence? {
        guard let span = CivilDayRange(first: day, last: day.adding(days: Self.lookahead)) else { return nil }
        return occurrences(window: window, overlapping: span).first
    }

    /// How far ahead to look for the next occurrence: past a full year, for annual events.
    static let lookahead = 400
}
