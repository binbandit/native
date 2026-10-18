import Foundation

/// Where a review comment attaches: a line, or a range of lines ending at `line`, on one side of a
/// file's diff. GitHub's `line`/`side` with optional `startLine`/`startSide`.
public struct ReviewAnchor: Hashable, Sendable, Codable {
    public var path: String
    public var side: DiffSide
    public var line: Int
    /// The first line of a multi-line comment; `nil` for one line.
    public var startLine: Int?
    public var startSide: DiffSide?

    public init(
        path: String, side: DiffSide, line: Int, startLine: Int? = nil, startSide: DiffSide? = nil
    ) {
        self.path = path
        self.side = side
        self.line = line
        // GitHub rejects a range that starts where it ends.
        self.startLine = startLine == line && (startSide ?? side) == side ? nil : startLine
        self.startSide = self.startLine == nil ? nil : (startSide ?? side)
    }

    /// "line 12" or "lines 10–14", for labels and prompts.
    public var lineDescription: String {
        guard let startLine else { return "line \(line)" }
        return "lines \(startLine)–\(line)"
    }
}
