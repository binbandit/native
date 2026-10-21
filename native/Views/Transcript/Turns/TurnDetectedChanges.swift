import ACP
import Foundation

/// The latest turn's files from its recorded working-tree baseline, including shell edits and
/// reported edits that are outside the repository or were undone. Newly detected paths are absolute.
nonisolated struct TurnDetectedChanges: Hashable, Sendable {
    let startedAt: Date
    let files: [TurnSummary.ChangedFile]
}
