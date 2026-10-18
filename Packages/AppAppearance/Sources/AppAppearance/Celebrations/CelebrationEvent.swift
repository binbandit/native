import Foundation

/// A celebration that passed validation, with its icon set resolved: what the catalogue lists and
/// the policy chooses from.
public struct CelebrationEvent: Hashable, Sendable, Identifiable {
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
    /// The icon set it refers to, when an enabled plugin provides it.
    public let iconSet: IconSet?

    public init(contribution: CelebrationContribution, pluginID: String, order: Int, iconSet: IconSet?) {
        self.contribution = contribution
        self.pluginID = pluginID
        self.order = order
        self.iconSet = iconSet
    }

    public var id: CelebrationID { contribution.id }
    public var display: CelebrationDisplay { contribution.display }

    public var appIcon: AppearanceSurfaceStatus {
        iconSet?.appIcon ?? missingArtwork
    }

    public var home: AppearanceSurfaceStatus {
        iconSet?.homeStatus ?? missingArtwork
    }

    /// What Home draws, when that surface is ready.
    public var homeLook: HomeLook? {
        home.isReady ? iconSet?.home : nil
    }

    public func icon(for variant: AppIconVariant, isDark: Bool) -> AppIconImage? {
        appIcon.isReady ? iconSet?.icon(for: variant, isDark: isDark) : nil
    }

    /// Whether anything is ready to apply: an edition with neither surface can be browsed, not used.
    public var isApplicable: Bool { appIcon.isReady || home.isReady }

    /// Whether someone can turn it on: its dates resolve, and it has artwork here or to download.
    public func canBeChosen(on day: CivilDate) -> Bool {
        dateStatus(on: day) == .resolvable && (isApplicable || appIcon.isDownloadable)
    }

    /// The edition whose pack the icon downloads from, if it does.
    public var iconPack: String? {
        guard case .pack(let edition)? = iconSet?.contribution.icons else { return nil }
        return edition
    }

    private var missingArtwork: AppearanceSurfaceStatus {
        guard let reference = contribution.iconSet else { return .forthcoming }
        return .unavailable("Its icon set \"\(reference)\" isn't installed or is turned off.")
    }

    public func dateStatus(on day: CivilDate) -> DateStatus {
        if case .unsupported(let kind) = contribution.calendar.rule { return .unsupportedCalendar(kind) }
        if let last = contribution.provenance.coverage?.through ?? contribution.calendar.rule.lastTabledYear,
            day.year > last
        {
            return .coverageEnded(lastYear: last)
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
