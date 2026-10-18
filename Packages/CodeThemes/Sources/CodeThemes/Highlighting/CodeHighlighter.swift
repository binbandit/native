/// A run of code drawn in one role's color.
public struct CodeSegment: Sendable, Hashable {
    public let text: String
    public let role: CodeTokenRole

    public init(_ text: String, _ role: CodeTokenRole) {
        self.text = text
        self.role = role
    }
}

/// Colors code by role: with the language's tree-sitter grammar when CodeThemes bundles one
/// (`TreeSitterHighlighter`), otherwise, or when the grammar can't parse it, with the lexer
/// (`CodeLexer`). Either way it never fails and never changes the text, only its colors.
public enum CodeHighlighter {
    /// Code past this many characters draws plain, so a pasted log can't stall a frame.
    public static let maximumLength = 200_000

    /// The code as consecutive segments; joined, their text is exactly `code`.
    public static func segments(_ code: String, language: CodeLanguage?) -> [CodeSegment] {
        guard let language, code.utf8.count <= maximumLength else {
            return code.isEmpty ? [] : [CodeSegment(code, .foreground)]
        }
        if let grammar = language.treeSitter, let segments = TreeSitterHighlighter.segments(code, grammar: grammar) {
            return segments
        }
        return CodeLexer.segments(code, language: language)
    }

    /// `segments`, the colors of `previous`, reused for `code` until it's highlighted itself: the start
    /// the two share keeps its colors and the rest draws plain. Joined, the result is exactly `code`.
    public static func segments(_ segments: [CodeSegment], of previous: String, reusedFor code: String)
        -> [CodeSegment]
    {
        // Scalars rather than characters: segments split where captures do, which can be inside a
        // grapheme cluster, so only scalar counts are sure to add up to `previous`.
        var remaining = zip(previous.unicodeScalars, code.unicodeScalars).prefix { $0 == $1 }.count
        let shared = remaining
        var reused: [CodeSegment] = []
        for segment in segments where remaining > 0 {
            let scalars = segment.text.unicodeScalars
            if scalars.count <= remaining {
                reused.append(segment)
                remaining -= scalars.count
            } else {
                reused.append(CodeSegment(String(scalars.prefix(remaining)), segment.role))
                remaining = 0
            }
        }
        let rest = code.unicodeScalars.dropFirst(shared)
        if !rest.isEmpty {
            reused.append(CodeSegment(String(rest), .foreground))
        }
        return reused
    }

    /// The code's lines, each as segments (without the line break), for drawing line by line (diffs).
    /// Tokens spanning lines, like block comments, keep their color on every line.
    public static func lines(_ code: String, language: CodeLanguage?) -> [[CodeSegment]] {
        lines(segments: segments(code, language: language), endsWithNewline: code.hasSuffix("\n"))
    }

    /// Highlighted segments split into lines.
    static func lines(segments: [CodeSegment], endsWithNewline: Bool) -> [[CodeSegment]] {
        var lines: [[CodeSegment]] = [[]]
        for segment in segments {
            let parts = segment.text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    lines.append([])
                }
                if !part.isEmpty {
                    lines[lines.count - 1].append(CodeSegment(String(part), segment.role))
                }
            }
        }
        if endsWithNewline {
            lines.removeLast()
        }
        return lines
    }
}
