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
        let last = first.adding(days: days - 1)
        var day = first
        var result: [CelebrationOverlap] = []
        while day <= last {
            let resolution = resolve(events, preferences: preferences, on: day, canApplyAppIcon: canApplyAppIcon)
            let end = min(resolution.nextChange?.adding(days: -1) ?? last, last)
            defer { day = end.adding(days: 1) }
            guard let active = resolution.active, case .priority = active.reason,
                let range = CivilDayRange(first: day, last: end)
            else { continue }
            let tied = ([active.occurrence] + resolution.runnersUp)
                .filter { $0.tier(on: day) == active.tier }
                .map(\.eventID).sorted { $0.rawValue < $1.rawValue }
            for (index, a) in tied.enumerated() {
                for b in tied.dropFirst(index + 1) where a != b {
                    if let previous = result.lastIndex(where: {
                        $0.first == a && $0.second == b && $0.tier == active.tier && $0.days.last.adding(days: 1) == day
                    }), let merged = CivilDayRange(first: result[previous].days.first, last: end) {
                        result[previous] = CelebrationOverlap(first: a, second: b, days: merged, tier: active.tier)
                    } else {
                        result.append(CelebrationOverlap(first: a, second: b, days: range, tier: active.tier))
                    }
                }
            }
        }
        return result.sorted { ($0.days.first, $0.id) < ($1.days.first, $1.id) }
    }
}
