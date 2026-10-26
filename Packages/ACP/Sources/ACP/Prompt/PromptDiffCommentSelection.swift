/// A comment range stays on one side of one hunk. Unlike a bare quote, it never joins versions.
public struct PromptDiffCommentSelection: Sendable {
    public struct Row: Sendable {
        public let before: PromptQuote.Line?
        public let after: PromptQuote.Line?
        public init(before: PromptQuote.Line?, after: PromptQuote.Line?) {
            self.before = before
            self.after = after
        }
    }

    public static func quote(
        source: String, rows: [Row], range: ClosedRange<Int>, side: PromptQuote.Side
    ) -> PromptQuote? {
        guard side != .transcript, rows.indices.contains(range.lowerBound), rows.indices.contains(range.upperBound),
            !rows[range].contains(where: { $0.before == nil && $0.after == nil })
        else { return nil }
        let lines = range.compactMap { side == .old ? rows[$0].before : rows[$0].after }
        guard !lines.isEmpty else { return nil }
        for pair in zip(lines, lines.dropFirst()) where pair.1.number != pair.0.number + 1 { return nil }
        return PromptQuote(source: source, side: side, lines: lines)
    }
}
