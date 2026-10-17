/// Back and forward through what the user has looked at, like a browser: visiting something new
/// drops whatever was ahead, and moving skips entries that have since gone away.
nonisolated struct NavigationHistory<Entry: Equatable>: Equatable {
    enum Direction {
        case back, forward

        fileprivate var step: Int {
            switch self {
            case .back: -1
            case .forward: 1
            }
        }
    }

    private(set) var entries: [Entry] = []
    /// The entry on screen, or the one that was last when nothing is.
    private(set) var position = -1

    mutating func visit(_ entry: Entry) {
        if entries.indices.contains(position), entries[position] == entry { return }
        entries = Array(entries.prefix(position + 1)) + [entry]
        position = entries.count - 1
    }

    /// Whether moving in `direction` from `current` would land anywhere.
    func canMove(_ direction: Direction, from current: Entry?, isAvailable: (Entry) -> Bool) -> Bool {
        destination(direction, from: current, isAvailable: isAvailable) != nil
    }

    /// Moves in `direction` and returns the entry to show, if there's one to go to.
    mutating func move(_ direction: Direction, from current: Entry?, isAvailable: (Entry) -> Bool) -> Entry? {
        guard let destination = destination(direction, from: current, isAvailable: isAvailable) else { return nil }
        position = destination
        return entries[destination]
    }

    private func destination(_ direction: Direction, from current: Entry?, isAvailable: (Entry) -> Bool) -> Int? {
        // With nothing on screen, going back starts from the entry that was showing last.
        var index = current == nil && direction == .back ? position : position + direction.step
        while entries.indices.contains(index) {
            if entries[index] != current, isAvailable(entries[index]) {
                return index
            }
            index += direction.step
        }
        return nil
    }
}
