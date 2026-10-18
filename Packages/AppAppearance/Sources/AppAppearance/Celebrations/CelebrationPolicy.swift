/// The one celebration in effect on a day, and why. A single resolution drives both the app icon and
/// Home, so two editions are never blended.
public struct CelebrationResolution: Hashable, Sendable {
    public struct Active: Hashable, Sendable {
        public let occurrence: CelebrationOccurrence
        public let tier: CelebrationOccurrence.Tier
        /// Whether it changes the icon: chosen, artwork complete, and the platform can apply it.
        public let appliesToAppIcon: Bool
        public let appliesToHome: Bool
        public let reason: Reason

        public var eventID: CelebrationID { occurrence.eventID }
    }

    /// Why the active celebration won, for the chooser to explain.
    public enum Reason: Hashable, Sendable {
        /// Nothing else applies today.
        case only
        /// The user chose it for this occurrence.
        case chosen(over: CelebrationID)
        /// It's on its core dates and the other is only in a decorative window.
        case coreDates(over: CelebrationID)
        /// Both are on the same footing, and it comes first in the user's order.
        case priority(over: CelebrationID)
    }

    public let day: CivilDate
    /// Nil restores the base icon and Home.
    public let active: Active?
    /// Others that would apply today, in policy order, for "Show instead".
    public let runnersUp: [CelebrationOccurrence]
    /// Occurrences that would apply today but were skipped, so the user can bring them back.
    public let skipped: [CelebrationOccurrence]
    /// The next day the outcome can change; nil when nothing enabled ever occurs.
    public let nextChange: CivilDate?
}

/// One stretch of days with the same outcome, for "coming up".
public struct CelebrationScheduleSegment: Hashable, Sendable {
    public let days: CivilDayRange
    /// Nil is the base appearance.
    public let occurrence: CelebrationOccurrence?
}

/// The overlap policy, in order: the user's skip or choice for an occurrence first, then core dates
/// over another celebration's decorative window, then the user's order (catalogue order until they
/// set one). With nothing left, the base appearance returns.
public enum CelebrationPolicy {
    public static func resolve(
        _ events: [CelebrationEvent], preferences: CelebrationPreferences, on day: CivilDate,
        canApplyAppIcon: Bool = true
    ) -> CelebrationResolution {
        let order = preferences.order(in: events)
        var candidates: [Candidate] = []
        var skipped: [CelebrationOccurrence] = []
        for event in events.map(preferences.styled) {
            guard let surfaces = surfaces(of: event, preferences: preferences, canApplyAppIcon: canApplyAppIcon) else {
                continue
            }
            let selection = preferences.selection(for: event.id)
            for occurrence in event.occurrences(window: selection.window, overlapping: CivilDayRange(day: day)) {
                guard let tier = occurrence.tier(on: day) else { continue }
                if preferences.skipped.contains(occurrence.id) {
                    skipped.append(occurrence)
                    continue
                }
                candidates.append(
                    Candidate(
                        occurrence: occurrence, tier: tier, isChosen: preferences.chosen == occurrence.id,
                        rank: order.firstIndex(of: event.id) ?? order.count, surfaces: surfaces))
            }
        }
        candidates.sort()
        let active = candidates.first.map { winner in
            CelebrationResolution.Active(
                occurrence: winner.occurrence, tier: winner.tier, appliesToAppIcon: winner.surfaces.appIcon,
                appliesToHome: winner.surfaces.home,
                reason: candidates.dropFirst().first.map { reason(winner, over: $0) } ?? .only)
        }
        return CelebrationResolution(
            day: day, active: active, runnersUp: candidates.dropFirst().map(\.occurrence), skipped: skipped,
            nextChange: nextChange(
                after: day, events: events, preferences: preferences, canApplyAppIcon: canApplyAppIcon)
        )
    }

    /// The outcome day by day from `first` through `last`, merged into stretches.
    public static func schedule(
        _ events: [CelebrationEvent], preferences: CelebrationPreferences, from first: CivilDate,
        through last: CivilDate, canApplyAppIcon: Bool = true
    ) -> [CelebrationScheduleSegment] {
        var segments: [CelebrationScheduleSegment] = []
        var day = first
        while day <= last {
            let resolution = resolve(events, preferences: preferences, on: day, canApplyAppIcon: canApplyAppIcon)
            let end = min(resolution.nextChange?.adding(days: -1) ?? last, last)
            let occurrence = resolution.active?.occurrence
            if let previous = segments.last, previous.occurrence == occurrence,
                let merged = CivilDayRange(first: previous.days.first, last: end)
            {
                segments[segments.count - 1] = CelebrationScheduleSegment(days: merged, occurrence: occurrence)
            } else if let days = CivilDayRange(first: day, last: end) {
                segments.append(CelebrationScheduleSegment(days: days, occurrence: occurrence))
            }
            day = end.adding(days: 1)
        }
        return segments
    }

    // MARK: - Helpers

    private struct Surfaces: Hashable {
        let appIcon: Bool
        let home: Bool
    }

    private struct Candidate: Comparable {
        let occurrence: CelebrationOccurrence
        let tier: CelebrationOccurrence.Tier
        let isChosen: Bool
        let rank: Int
        let surfaces: Surfaces

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.isChosen != rhs.isChosen { return lhs.isChosen }
            if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return lhs.occurrence.core.first < rhs.occurrence.core.first
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.occurrence == rhs.occurrence
        }
    }

    /// What an enabled celebration would change, or nil when it changes nothing: switched off, or
    /// every chosen surface without artwork. Such a celebration never hides another.
    private static func surfaces(
        of event: CelebrationEvent, preferences: CelebrationPreferences, canApplyAppIcon: Bool
    ) -> Surfaces? {
        let selection = preferences.selection(for: event.id)
        guard selection.isEnabled else { return nil }
        let surfaces = Surfaces(
            appIcon: selection.appIcon && event.appIcon.isReady && canApplyAppIcon,
            home: selection.home && event.home.isReady)
        return surfaces.appIcon || surfaces.home ? surfaces : nil
    }

    private static func reason(_ winner: Candidate, over other: Candidate) -> CelebrationResolution.Reason {
        if winner.isChosen { return .chosen(over: other.occurrence.eventID) }
        if winner.tier > other.tier { return .coreDates(over: other.occurrence.eventID) }
        return .priority(over: other.occurrence.eventID)
    }

    /// The first day after `day` where any celebration that could apply starts, changes tier or ends.
    private static func nextChange(
        after day: CivilDate, events: [CelebrationEvent], preferences: CelebrationPreferences, canApplyAppIcon: Bool
    ) -> CivilDate? {
        guard let span = CivilDayRange(first: day, last: day.adding(days: CelebrationEvent.lookahead)) else {
            return nil
        }
        return
            events.map(preferences.styled)
            .filter { surfaces(of: $0, preferences: preferences, canApplyAppIcon: canApplyAppIcon) != nil }
            .flatMap { $0.occurrences(window: preferences.selection(for: $0.id).window, overlapping: span) }
            .flatMap(\.edges)
            .filter { $0 > day }
            .min()
    }
}
