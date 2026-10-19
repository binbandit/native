import Foundation
import Observation
import SwiftUI

/// The order the user dragged each project's sessions into, remembered across launches. Sessions
/// they haven't placed come first, most recent first, so new ones show up on top.
@Observable
final class SessionOrdering {
    private var orders: [Project.ID: [SessionKey]] {
        didSet { save() }
    }
    /// Pinned sessions, across projects, in the user's order.
    private(set) var pinned: [SessionKey] {
        didSet { defaults.set(try? JSONEncoder().encode(pinned), forKey: Self.pinnedKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "sessionOrder"
    private static let pinnedKey = "pinnedSessions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        orders =
            defaults.data(forKey: Self.key).flatMap {
                try? JSONDecoder().decode([Project.ID: [SessionKey]].self, from: $0)
            } ?? [:]
        pinned =
            defaults.data(forKey: Self.pinnedKey).flatMap { try? JSONDecoder().decode([SessionKey].self, from: $0) }
            ?? []
    }

    func isPinned(_ key: SessionKey) -> Bool {
        pinned.contains(key)
    }

    /// Pins at the end of the pinned list, or at `index`, for undoing an unpin.
    func pin(_ key: SessionKey, at index: Int? = nil) {
        guard !pinned.contains(key) else { return }
        pinned.insert(key, at: min(index ?? pinned.count, pinned.count))
    }

    /// Unpins, returning where the session was.
    @discardableResult
    func unpin(_ key: SessionKey) -> Int? {
        guard let index = pinned.firstIndex(of: key) else { return nil }
        pinned.remove(at: index)
        return index
    }

    func movePinned(_ displayed: [SessionKey], fromOffsets source: IndexSet, toOffset destination: Int) {
        var keys = displayed
        keys.move(fromOffsets: source, toOffset: destination)
        // Pins not on screen (their agent isn't running) keep their place at the end.
        pinned = keys + pinned.filter { !keys.contains($0) }
    }

    /// `sessions` in display order: unplaced ones by `recency`, newest first, then the user's order.
    func sorted(
        _ sessions: [SessionSummary], in project: Project.ID, recency: (SessionSummary) -> Date
    ) -> [SessionSummary] {
        let order = orders[project, default: []]
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        // Each session's recency once, not once per comparison: it can mean parsing a date.
        let unplaced = sessions.filter { positions[$0.id] == nil }
            .map { ($0, recency($0)) }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
        let placed = sessions.compactMap { session in positions[session.id].map { (session, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        return unplaced + placed
    }

    /// Moves sessions as the user dragged them within `displayed`, the project's sessions as shown.
    func move(
        _ displayed: [SessionKey], in project: Project.ID, fromOffsets source: IndexSet, toOffset destination: Int
    ) {
        var keys = displayed
        keys.move(fromOffsets: source, toOffset: destination)
        orders[project] = keys
    }

    /// The project's sessions in the order the user put them, if they did.
    func order(in project: Project.ID) -> [SessionKey]? {
        orders[project]
    }

    /// Gives `new` the place `old` had, in a project's order and among the pinned: `/clear`'s fresh
    /// conversation stays where the task was.
    func replace(_ old: SessionKey, with new: SessionKey) {
        if let index = pinned.firstIndex(of: old) {
            pinned[index] = new
        }
        for (project, order) in orders {
            if let index = order.firstIndex(of: old) {
                orders[project]?[index] = new
            }
        }
    }

    func restore(_ order: [SessionKey]?, in project: Project.ID) {
        orders[project] = order
    }

    func forget(_ project: Project.ID) {
        orders[project] = nil
    }

    private func save() {
        if let data = try? JSONEncoder().encode(orders) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
