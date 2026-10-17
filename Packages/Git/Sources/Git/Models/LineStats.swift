import Foundation

/// Lines added and removed in a file or a set of files.
public struct LineStats: Hashable, Sendable {
    public var additions: Int
    public var deletions: Int
    /// git saw binary content, so there are no line counts.
    public var isBinary: Bool

    public init(additions: Int = 0, deletions: Int = 0, isBinary: Bool = false) {
        self.additions = additions
        self.deletions = deletions
        self.isBinary = isBinary
    }

    public static let zero = LineStats()

    public static func + (lhs: LineStats, rhs: LineStats) -> LineStats {
        LineStats(additions: lhs.additions + rhs.additions, deletions: lhs.deletions + rhs.deletions, isBinary: lhs.isBinary || rhs.isBinary)
    }
}
