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

    @ObservationIgnored private let defaults: UserDefaults
    private static let key = "sessionOrder"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        orders = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Project.ID: [SessionKey]].self, from: $0) } ?? [:]
    }

    /// `sessions` in display order: unplaced ones by `recency`, newest first, then the user's order.
    func sorted(_ sessions: [SessionSummary], in project: Project.ID, recency: (SessionSummary) -> Date) -> [SessionSummary] {
        let order = orders[project, default: []]
        let positions = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let unplaced = sessions.filter { positions[$0.id] == nil }.sorted { recency($0) > recency($1) }
        let placed = sessions.compactMap { session in positions[session.id].map { (session, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        return unplaced + placed
    }

    /// Moves sessions as the user dragged them within `displayed`, the project's sessions as shown.
    func move(_ displayed: [SessionKey], in project: Project.ID, fromOffsets source: IndexSet, toOffset destination: Int) {
        var keys = displayed
        keys.move(fromOffsets: source, toOffset: destination)
        orders[project] = keys
    }

    /// The project's sessions in the order the user put them, if they did.
    func order(in project: Project.ID) -> [SessionKey]? {
        orders[project]
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
