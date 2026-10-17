import SwiftUI

/// Lines added and removed by a change.
public nonisolated struct DiffStats: Equatable, Hashable, Sendable {
    public var added: Int
    public var removed: Int

    public init(added: Int = 0, removed: Int = 0) {
        self.added = added
        self.removed = removed
    }

    /// Counts a file change the way `DiffView` draws it.
    public init(oldText: String?, newText: String) {
        self = DiffRow.rows(oldText: oldText, newText: newText).stats
    }

    public static func + (lhs: DiffStats, rhs: DiffStats) -> DiffStats {
        DiffStats(added: lhs.added + rhs.added, removed: lhs.removed + rhs.removed)
    }
}

/// `+3 −1` in green and red with tabular figures; a zero side is left out. Takes the caller's font.
public struct DiffStatsText: View {
    let stats: DiffStats

    public init(stats: DiffStats) {
        self.stats = stats
    }

    public var body: some View {
        HStack(spacing: DS.Space.xs) {
            if stats.added > 0 {
                Text(verbatim: "+\(DSFormat.lineCount(stats.added))").foregroundStyle(.dsSuccess)
            }
            if stats.removed > 0 {
                Text(verbatim: "\u{2212}\(DSFormat.lineCount(stats.removed))").foregroundStyle(.dsDanger)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats.added) lines added, \(stats.removed) removed")
    }
}
