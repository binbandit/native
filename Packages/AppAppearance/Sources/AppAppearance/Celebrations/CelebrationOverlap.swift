/// A pair of chosen celebrations whose equal-tier dates need the user's priority to decide.
public struct CelebrationOverlap: Hashable, Sendable, Identifiable {
    public let first: CelebrationID
    public let second: CelebrationID
    public let days: CivilDayRange
    public let tier: CelebrationOccurrence.Tier

    public var id: String { "\(first.rawValue)/\(second.rawValue)/\(days.first)" }
}

extension CelebrationPolicy {
    /// Only ties at the winning tier need a choice. Walking boundaries keeps a year of choices
    /// cheap, excludes skipped/unavailable surfaces, and uses exactly the resolver's precedence.
    public static func overlaps(
        _ events: [CelebrationEvent], preferences: CelebrationPreferences, from first: CivilDate,
        days: Int, canApplyAppIcon: Bool = true
    ) -> [CelebrationOverlap] {
        guard days > 0 else { return [] }
        guard let horizon = CivilDayRange(first: first, last: first.adding(days: days - 1)) else { return [] }
        // Resolve dates once. A full catalogue has many boundaries but only a few occurrences;
        // asking the calendar again at every boundary made the settings body unnecessarily costly.
        let occurrences = events.map(preferences.styled).flatMap { event -> [CelebrationOccurrence] in
            let selection = preferences.selection(for: event.id)
            guard selection.isEnabled,
                (selection.home && event.home.isReady)
                    || (selection.appIcon && event.appIcon.isReady && canApplyAppIcon)
            else { return [] }
            return event.occurrences(window: selection.window, overlapping: horizon)
                .filter { !preferences.skipped.contains($0.id) }
        }
        let edges = Set(
            occurrences.flatMap(\.edges).filter { horizon.contains($0) } + [first, horizon.last.adding(days: 1)]
        ).sorted()
        var result: [CelebrationOverlap] = []
        for (day, boundary) in zip(edges, edges.dropFirst()) {
            let end = boundary.adding(days: -1)
            let active = occurrences.filter { $0.display.contains(day) }
            guard !active.contains(where: { $0.id == preferences.chosen }),
                let tier = active.compactMap({ $0.tier(on: day) }).max(),
                let range = CivilDayRange(first: day, last: end)
            else { continue }
            let tied = active.filter { $0.tier(on: day) == tier }
                .map(\.eventID).sorted { $0.rawValue < $1.rawValue }
            for (index, a) in tied.enumerated() {
                for b in tied.dropFirst(index + 1) where a != b {
                    if let previous = result.lastIndex(where: {
                        $0.first == a && $0.second == b && $0.tier == tier && $0.days.last.adding(days: 1) == day
                    }), let merged = CivilDayRange(first: result[previous].days.first, last: end) {
                        result[previous] = CelebrationOverlap(first: a, second: b, days: merged, tier: tier)
                    } else {
                        result.append(CelebrationOverlap(first: a, second: b, days: range, tier: tier))
                    }
                }
            }
        }
        return result.sorted { ($0.days.first, $0.id) < ($1.days.first, $1.id) }
    }
}
