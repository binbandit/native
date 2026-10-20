import Foundation
import Git

/// How a task's working tree looked when one of its turns began, so Review can show exactly what
/// the turn changed, committed or not. `GitTurnBaselines` records one as each turn starts.
nonisolated struct GitTurnBaseline: Codable, Hashable, Sendable {
    let session: SessionKey
    /// The turn's `TranscriptTurn.startedAt`, which identifies it within the session.
    let startedAt: Date
    /// The working tree's root, as git spelled it.
    let root: String
    let snapshot: WorkingTreeSnapshot

    /// Whether this is the baseline of the turn that began at `date`. Dates cross the host's wire
    /// and the defaults as JSON, so they're compared to the millisecond.
    func began(at date: Date) -> Bool {
        abs(startedAt.timeIntervalSince(date)) < 0.001
    }
}
