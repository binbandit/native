import ACP

extension SessionState {
    /// Where usage limits stopped turns, keyed by the item each card replaces, with whether it's in
    /// the latest turn (the only one whose card can act).
    var usageLimitStops: [String: (stop: UsageLimitStop, isLatestTurn: Bool)] {
        let turns = turns
        var stops: [String: (stop: UsageLimitStop, isLatestTurn: Bool)] = [:]
        for (position, turn) in turns.enumerated() {
            guard let stop = UsageLimitStop(turnItems: items[turn.items], stopReason: turn.stopReason) else { continue }
            for id in stop.itemIDs {
                stops[id] = (stop, position == turns.count - 1)
            }
        }
        return stops
    }
}
