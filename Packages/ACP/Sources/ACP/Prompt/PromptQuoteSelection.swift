/// A range in a displayed diff. Selecting two numbers on the same side quotes that file only;
/// selecting across sides retains both versions with separate source identities.
public struct PromptQuoteSelection: Sendable {
    public struct Row: Sendable {
        public let side: PromptQuote.Side
        public let line: PromptQuote.Line?

        public init(side: PromptQuote.Side, line: PromptQuote.Line?) {
            self.side = side
            self.line = line
        }
    }

    public let indices: [Int]
    public let quotes: [PromptQuote]

    public init(source: String, rows: [Row], range: ClosedRange<Int>) {
        guard rows.indices.contains(range.lowerBound), rows.indices.contains(range.upperBound) else {
            indices = []; quotes = []; return
        }
        let first = rows[range.lowerBound].side
        let side = first == rows[range.upperBound].side ? first : nil
        indices = range.filter { rows[$0].line != nil && (side == nil || rows[$0].side == side) }
        var result: [PromptQuote] = []
        var lines: [PromptQuote.Line] = []
        var currentSide = first
        func flush() {
            if !lines.isEmpty {
                result.append(PromptQuote(source: source, side: currentSide, lines: lines))
                lines = []
            }
        }
        for index in range {
            let row = rows[index]
            guard let line = row.line else { flush(); continue }
            guard side == nil || row.side == side else { continue }
            if row.side != currentSide { flush(); currentSide = row.side }
            if let previous = lines.last, line.number != previous.number + 1 { flush() }
            lines.append(line)
        }
        flush()
        quotes = result
    }
}
