/// Code typed into a prompt draft, as the composer edits it. In a fenced block, Return makes a new
/// line (indented like the one before) and Tab indents rather than sending and moving focus. What
/// counts as code is `FencedText`'s, the same the transcript renders.
public enum PromptCode {
    /// The draft after an edit, and what's selected in it.
    public struct Edit: Equatable, Sendable {
        public var text: String
        public var selection: Range<String.Index>
    }

    /// Whether `cursor` is in a fenced block: past the start of its opening fence and, for a closed
    /// block, before the end of its closing fence. An unclosed block runs to the end of the draft, so
    /// the caret is in one from the moment its fence is typed.
    public static func isInBlock(_ cursor: String.Index, in text: String) -> Bool {
        FencedText.blocks(in: text).contains { block($0, holds: cursor) }
    }

    /// Whether `cursor` is in any code: a fenced block, or between an inline span's backticks.
    public static func isInCode(_ cursor: String.Index, in text: String) -> Bool {
        isInBlock(cursor, in: text)
            || FencedText.inlineCode(in: text).contains { $0.lowerBound < cursor && cursor < $0.upperBound }
    }

    /// What the composer sets as code: every fenced block, fence lines included, and every inline
    /// span, backticks included.
    public static func ranges(in text: String) -> [Range<String.Index>] {
        FencedText.blocks(in: text).map(\.range) + FencedText.inlineCode(in: text)
    }

    /// Return in a block: the selection becomes a line break, and the new line starts with the
    /// indentation the caret's line has before it.
    public static func newline(in text: String, replacing selection: Range<String.Index>) -> Edit {
        let start = lineStart(of: selection.lowerBound, in: text)
        let inserted = "\n" + text[start..<selection.lowerBound].prefix { $0 == " " || $0 == "\t" }
        var result = text
        result.replaceSubrange(selection, with: inserted)
        return caret(at: offset(of: selection.lowerBound, in: text) + inserted.utf8.count, in: result)
    }

    /// Tab in a block: one indent at the caret, or before each selected line that isn't empty,
    /// leaving those lines selected.
    public static func indent(in text: String, selection: Range<String.Index>) -> Edit {
        let unit = indentUnit(at: selection.lowerBound, in: text)
        guard !selection.isEmpty else {
            var result = text
            result.insert(contentsOf: unit, at: selection.lowerBound)
            return caret(at: offset(of: selection.lowerBound, in: text) + unit.utf8.count, in: result)
        }
        return replacingLines(of: selection, in: text) { $0.isEmpty ? "" : unit + $0 }
    }

    /// Shift-Tab in a block: one indent (a tab, or up to an indent's worth of spaces) off the caret's
    /// line or each selected line.
    public static func outdent(in text: String, selection: Range<String.Index>) -> Edit {
        // A block indented with tabs still loses up to four spaces from a line indented with them.
        let unit = indentUnit(at: selection.lowerBound, in: text)
        let width = unit == "\t" ? 4 : unit.count
        let outdented = { (line: Substring) -> Substring in
            line.first == "\t" ? line.dropFirst() : line.dropFirst(min(width, line.prefix { $0 == " " }.count))
        }
        guard selection.isEmpty else { return replacingLines(of: selection, in: text) { String(outdented($0)) } }
        let start = lineStart(of: selection.lowerBound, in: text)
        let end = lineEnd(of: selection.lowerBound, in: text)
        let kept = outdented(text[start..<end])
        let removed = text[start..<end].utf8.count - kept.utf8.count
        let result = String(text[..<start]) + kept + text[end...]
        let cursor = max(offset(of: start, in: text), offset(of: selection.lowerBound, in: text) - removed)
        return caret(at: cursor, in: result)
    }

    // MARK: - Lines

    private static func block(_ block: FencedBlock, holds cursor: String.Index) -> Bool {
        block.range.lowerBound < cursor && (cursor < block.range.upperBound || !block.isClosed)
    }

    /// The block's own indent: a tab if its lines use tabs, else its smallest indent of two to eight
    /// spaces, else four spaces.
    private static func indentUnit(at cursor: String.Index, in text: String) -> String {
        guard let block = FencedText.blocks(in: text).first(where: { block($0, holds: cursor) }) else {
            return "    "
        }
        let lines = text[block.contentRange].split(separator: "\n")
        if lines.contains(where: { $0.first == "\t" }) {
            return "\t"
        }
        let indents = lines.map { $0.prefix { $0 == " " }.count }.filter { $0 >= 2 }
        return String(repeating: " ", count: min(indents.min() ?? 4, 8))
    }

    /// `transform` applied to each line the selection touches, which end up selected whole. A
    /// selection ending at the start of a line leaves that line alone.
    private static func replacingLines(
        of selection: Range<String.Index>, in text: String, _ transform: (Substring) -> String
    ) -> Edit {
        let start = lineStart(of: selection.lowerBound, in: text)
        var last = selection.upperBound
        if last > selection.lowerBound, text[text.index(before: last)] == "\n" {
            last = text.index(before: last)
        }
        let end = lineEnd(of: last, in: text)
        let lines = text[start..<end].split(separator: "\n", omittingEmptySubsequences: false).map(transform)
        let replaced = lines.joined(separator: "\n")
        let result = String(text[..<start]) + replaced + text[end...]
        let from = offset(of: start, in: text)
        return Edit(text: result, selection: index(from, in: result)..<index(from + replaced.utf8.count, in: result))
    }

    private static func lineStart(of index: String.Index, in text: String) -> String.Index {
        text[..<index].lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
    }

    private static func lineEnd(of index: String.Index, in text: String) -> String.Index {
        text[index...].firstIndex(of: "\n") ?? text.endIndex
    }

    private static func caret(at offset: Int, in text: String) -> Edit {
        let cursor = index(offset, in: text)
        return Edit(text: text, selection: cursor..<cursor)
    }

    private static func offset(of index: String.Index, in text: String) -> Int {
        text.utf8.distance(from: text.startIndex, to: index)
    }

    private static func index(_ offset: Int, in text: String) -> String.Index {
        text.utf8.index(text.startIndex, offsetBy: offset)
    }
}
