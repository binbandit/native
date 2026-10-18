/// What the user chose, kept apart from any manifest so updating or removing a plugin never rewrites
/// it. Every celebration starts off; nothing is inferred from locale.
public struct CelebrationPreferences: Codable, Hashable, Sendable {
    /// One celebration's choices.
    public struct Selection: Codable, Hashable, Sendable {
        /// "Celebrate automatically": apply it on its dates.
        public var isEnabled: Bool
        public var appIcon: Bool
        public var home: Bool
        /// The display window; nil follows the celebration's default.
        public var window: CelebrationWindow.ID?

        public init(isEnabled: Bool = false, appIcon: Bool = true, home: Bool = true, window: CelebrationWindow.ID? = nil)
        {
            self.isEnabled = isEnabled
            self.appIcon = appIcon
            self.home = home
            self.window = window
        }
    }

    public var selections: [CelebrationID: Selection]
    /// The user's order for overlapping celebrations, most preferred first. Celebrations not in it
    /// follow in catalogue order.
    public var priority: [CelebrationID]
    /// Occurrences the user skipped, until they end.
    public var skipped: Set<CelebrationOccurrence.ID>
    /// An occurrence the user asked to show over the policy's pick while it lasts.
    public var chosen: CelebrationOccurrence.ID?

    public init(
        selections: [CelebrationID: Selection] = [:], priority: [CelebrationID] = [],
        skipped: Set<CelebrationOccurrence.ID> = [], chosen: CelebrationOccurrence.ID? = nil
    ) {
        self.selections = selections
        self.priority = priority
        self.skipped = skipped
        self.chosen = chosen
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selections = try container.decodeIfPresent([CelebrationID: Selection].self, forKey: .selections) ?? [:]
        priority = try container.decodeIfPresent([CelebrationID].self, forKey: .priority) ?? []
        skipped = try container.decodeIfPresent(Set<CelebrationOccurrence.ID>.self, forKey: .skipped) ?? []
        chosen = try container.decodeIfPresent(CelebrationOccurrence.ID.self, forKey: .chosen)
    }

    public func selection(for id: CelebrationID) -> Selection {
        selections[id] ?? Selection()
    }

    // MARK: - Migration

    /// Halloween's stable id, which the app icon's old opt-in becomes.
    public static let halloween = CelebrationID("native.halloween")

    /// Carries the app icon's Halloween switch (`appIconHalloweenEnabled`) over: it changed both the
    /// icon and Home in the season window, so the migrated selection does too.
    public static func migrating(legacyHalloweenEnabled: Bool) -> CelebrationPreferences {
        guard legacyHalloweenEnabled else { return CelebrationPreferences() }
        return CelebrationPreferences(selections: [halloween: Selection(isEnabled: true)], priority: [halloween])
    }

    // MARK: - Changes

    public mutating func setEnabled(_ isEnabled: Bool, for id: CelebrationID) {
        selections[id, default: Selection()].isEnabled = isEnabled
        if isEnabled, !priority.contains(id) { priority.append(id) }
    }

    /// The enabled celebrations in overlap order: the user's order, then the rest by catalogue order.
    public func order(in events: [CelebrationEvent]) -> [CelebrationID] {
        let enabled = events.filter { selection(for: $0.id).isEnabled }
        let ranked = priority.filter { id in enabled.contains { $0.id == id } }
        return ranked + enabled.map(\.id).filter { !ranked.contains($0) }
    }

    /// Moves a celebration earlier (negative) or later in the overlap order.
    public mutating func move(_ id: CelebrationID, by offset: Int, in events: [CelebrationEvent]) {
        var order = order(in: events)
        guard let index = order.firstIndex(of: id) else { return }
        let target = min(max(index + offset, 0), order.count - 1)
        order.insert(order.remove(at: index), at: target)
        // Keep the positions of celebrations that are switched off, so switching one back on restores it.
        priority = order + priority.filter { !order.contains($0) }
    }

    /// Forgets skips and a choice for occurrences that started long enough ago to be over.
    public mutating func prune(before day: CivilDate) {
        let cutoff = day.adding(days: -CelebrationEvent.lookahead)
        skipped = skipped.filter { $0.coreStart >= cutoff }
        if let chosen, chosen.coreStart < cutoff { self.chosen = nil }
    }
}
