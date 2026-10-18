/// Lines being picked for a comment in a diff's gutter, by dragging or shift-clicking: where the
/// pick started and how far it reaches, kept to what GitHub accepts. A comment's lines stay in one
/// hunk and on one side, so a pick that's pulled past either stops at the last line that counts and
/// says why, until it's pulled back.
public struct ReviewLineSelection: Hashable, Sendable {
    /// Why the pick stopped short of where it was pulled.
    public enum Limit: Hashable, Sendable {
        /// Past the start or end of the hunk: GitHub needs a comment's lines in one hunk.
        case hunkEdge
        /// Onto a line of the other side (a removed line from an added one, or back): GitHub needs a
        /// comment's lines on one side.
        case otherSide

        public var explanation: String {
            switch self {
            case .hunkEdge: "A comment's lines have to be in one hunk."
            case .otherSide: "A comment's lines have to be on one side: all removed, or all added and unchanged."
            }
        }
    }

    public let path: String
    public let hunk: DiffHunk
    /// The line the pick started on, as an index into the hunk's lines.
    public let start: Int
    /// The line it reaches now.
    public private(set) var end: Int
    /// Why it stops short of where it was last pulled, if it does.
    public private(set) var limit: Limit?

    /// A pick starting on line `index` of `hunk`, or nil when that line can't take a comment.
    public init?(path: String, hunk: DiffHunk, line index: Int) {
        guard hunk.lines.indices.contains(index), hunk.lines[index].anchor != nil else { return nil }
        self.path = path
        self.hunk = hunk
        start = index
        end = index
    }

    /// The side every line of the pick is on.
    public var side: DiffSide {
        // A pick only starts on a line with an anchor.
        hunk.lines[start].anchor?.side ?? .right
    }

    /// The picked lines, as indices into the hunk's lines, top to bottom.
    public var lines: ClosedRange<Int> { min(start, end)...max(start, end) }

    /// What the comment attaches to: one line, or the range from the top line to the bottom one.
    public var anchor: ReviewAnchor {
        let first = hunk.lines[lines.lowerBound].anchor?.line
        let last = hunk.lines[lines.upperBound].anchor?.line ?? 0
        return ReviewAnchor(path: path, side: side, line: last, startLine: first, startSide: side)
    }

    /// Reaches toward line `index` of the hunk (out of range when pulled past an end): as far as the
    /// last line on the pick's side before it, and no further than the hunk's edge.
    public mutating func extend(to index: Int) {
        limit = nil
        var target = index
        if !hunk.lines.indices.contains(target) {
            target = min(max(target, 0), hunk.lines.count - 1)
            limit = .hunkEdge
        }
        let step = target < start ? -1 : 1
        var reached = start
        var position = start
        while position != target {
            position += step
            guard let anchor = hunk.lines[position].anchor else { continue }
            if anchor.side == side {
                reached = position
            } else if position == target {
                limit = limit ?? .otherSide
            }
        }
        end = reached
    }
}
