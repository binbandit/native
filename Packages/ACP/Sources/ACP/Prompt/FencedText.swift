import Foundation

/// A piece of what the user typed: plain text, kept exactly as typed, or a fenced code block.
public enum FencedTextSegment: Hashable, Sendable {
    case text(String)
    /// A fenced block's code (without its fence lines) and the language its info string names.
    /// `isClosed` is false when the text ended before a closing fence.
    case code(String, language: String?, isClosed: Bool)
}

/// One fenced code block, located in the text it came from.
public struct FencedBlock: Hashable, Sendable {
    /// From the start of the opening fence line to the end of the closing one (without its line
    /// break), or to the end of the text when the block is never closed.
    public var range: Range<String.Index>
    /// The code between the fence lines, without the line breaks next to them.
    public var contentRange: Range<String.Index>
    /// The first word of the opening fence's info string.
    public var language: String?
    public var isClosed: Bool
    /// The opening fence's indent, which each code line loses as much of as it has.
    var indent: Int
}

/// Finds code in a user's message the way CommonMark (and GitHub) does, so the composer and the
/// transcript agree on what's code. A fenced block opens at a line of three or more backticks or
/// tildes, indented at most three spaces, with an optional info string whose first word is the
/// language; it closes at a line of the same character, at least as long, with nothing else on it;
/// a block that's never closed runs to the end of the message. Outside blocks, a run of backticks
/// opens an inline code span that the next run of exactly as many closes. Everything else is plain
/// text and stays exactly as typed.
public enum FencedText {
    public static func blocks(in text: String) -> [FencedBlock] {
        var blocks: [FencedBlock] = []
        var open: (fence: Fence, start: String.Index, contentStart: String.Index)?
        var lineStart = text.startIndex
        while true {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd]
            let nextLine = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            if let block = open {
                if Fence(closing: line, for: block.fence) != nil {
                    // The code ends before the line break that precedes the closing fence.
                    let contentEnd = lineStart > block.contentStart ? text.index(before: lineStart) : block.contentStart
                    blocks.append(
                        FencedBlock(
                            range: block.start..<lineEnd, contentRange: block.contentStart..<contentEnd,
                            language: block.fence.language, isClosed: true, indent: block.fence.indent))
                    open = nil
                }
            } else if let fence = Fence(opening: line) {
                open = (fence, lineStart, nextLine)
            }
            guard lineEnd < text.endIndex else { break }
            lineStart = nextLine
        }
        if let block = open {
            blocks.append(
                FencedBlock(
                    range: block.start..<text.endIndex, contentRange: block.contentStart..<text.endIndex,
                    language: block.fence.language, isClosed: false, indent: block.fence.indent))
        }
        return blocks
    }

    /// The text as plain pieces and code blocks, in order. Plain pieces leave out the line breaks
    /// next to a fence, and empty ones are dropped.
    public static func segments(of text: String) -> [FencedTextSegment] {
        var segments: [FencedTextSegment] = []
        var cursor = text.startIndex
        func appendText(upTo end: String.Index) {
            var piece = text[cursor..<end]
            if piece.last == "\n" { piece = piece.dropLast() }
            if !piece.isEmpty { segments.append(.text(String(piece))) }
        }
        for block in blocks(in: text) {
            appendText(upTo: block.range.lowerBound)
            segments.append(.code(code(of: block, in: text), language: block.language, isClosed: block.isClosed))
            cursor = block.range.upperBound
            if cursor < text.endIndex, text[cursor] == "\n" { cursor = text.index(after: cursor) }
        }
        appendText(upTo: text.endIndex)
        return segments
    }

    /// Whether the text holds a fenced code block at all, for callers that render plain text faster.
    public static func containsFence(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { Fence(opening: $0) != nil }
    }

    /// The inline code spans outside fenced blocks, each range covering its backticks. A run of
    /// backticks no run of the same length closes stays plain text, and so does one after a
    /// backslash.
    public static func inlineCode(in text: String) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        var regionStart = text.startIndex
        for block in blocks(in: text) {
            spans += inlineCode(in: text, within: regionStart..<block.range.lowerBound)
            regionStart = block.range.upperBound
        }
        spans += inlineCode(in: text, within: regionStart..<text.endIndex)
        return spans
    }

    private static func inlineCode(in text: String, within region: Range<String.Index>) -> [Range<String.Index>] {
        var spans: [Range<String.Index>] = []
        var index = region.lowerBound
        while let opening = text[index..<region.upperBound].firstIndex(of: "`") {
            if opening > region.lowerBound, text[text.index(before: opening)] == "\\" {
                index = text.index(after: opening)
                continue
            }
            let run = backtickRun(in: text, at: opening, before: region.upperBound)
            var search = run.upperBound
            var closing: Range<String.Index>?
            while let next = text[search..<region.upperBound].firstIndex(of: "`") {
                let candidate = backtickRun(in: text, at: next, before: region.upperBound)
                if candidate.count(in: text) == run.count(in: text) {
                    closing = candidate
                    break
                }
                search = candidate.upperBound
            }
            if let closing {
                spans.append(opening..<closing.upperBound)
                index = closing.upperBound
            } else {
                index = run.upperBound
            }
        }
        return spans
    }

    private static func backtickRun(
        in text: String, at start: String.Index, before end: String.Index
    ) -> Range<
        String.Index
    > {
        let runEnd = text[start..<end].firstIndex { $0 != "`" } ?? end
        return start..<runEnd
    }

    /// A block's code, each line losing up to the opening fence's own indent.
    private static func code(of block: FencedBlock, in text: String) -> String {
        guard block.indent > 0 else { return String(text[block.contentRange]) }
        return text[block.contentRange]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in line.dropFirst(min(block.indent, line.prefix { $0 == " " }.count)) }
            .joined(separator: "\n")
    }
}

private extension Range where Bound == String.Index {
    func count(in text: String) -> Int {
        text.distance(from: lowerBound, to: upperBound)
    }
}

private struct Fence {
    let character: Character
    let length: Int
    let indent: Int
    var language: String?

    init?(opening line: Substring) {
        guard let (character, length, indent, rest) = Self.parse(line) else { return nil }
        let info = rest.trimmingCharacters(in: .whitespaces)
        // A backtick fence's info string can't hold a backtick (that would be inline code).
        if character == "`", info.contains("`") { return nil }
        self.character = character
        self.length = length
        self.indent = indent
        let word = info.prefix { !$0.isWhitespace }
        language = word.isEmpty ? nil : String(word)
    }

    init?(closing line: Substring, for opening: Fence) {
        guard let (character, length, indent, rest) = Self.parse(line), character == opening.character,
            length >= opening.length, rest.allSatisfy(\.isWhitespace)
        else { return nil }
        self.character = character
        self.length = length
        self.indent = indent
    }

    /// The fence character, its run's length, the indent before it, and what follows the run.
    private static func parse(_ line: Substring) -> (Character, Int, Int, Substring)? {
        let indent = line.prefix { $0 == " " }.count
        guard indent <= 3 else { return nil }
        let rest = line.dropFirst(indent)
        guard let character = rest.first, character == "`" || character == "~" else { return nil }
        let length = rest.prefix { $0 == character }.count
        guard length >= 3 else { return nil }
        return (character, length, indent, rest.dropFirst(length))
    }
}
