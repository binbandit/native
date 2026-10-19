import Foundation

/// A piece of what the user typed: plain text, kept exactly as typed, or a fenced code block.
public enum FencedTextSegment: Hashable, Sendable {
    case text(String)
    /// A fenced block's code (without its fence lines) and the language its info string names.
    /// `isClosed` is false when the text ended before a closing fence.
    case code(String, language: String?, isClosed: Bool)
}

/// Finds the fenced code blocks in a user's message the way CommonMark (and GitHub) does, so the
/// composer and the transcript agree on what's code: a fence is a line of three or more backticks
/// or tildes, indented at most three spaces, with an optional info string whose first word is the
/// language; a line of the same character, at least as long, with nothing else on it closes it; and
/// a fence that's never closed runs to the end of the message. Everything else stays plain text.
public enum FencedText {
    public static func segments(of text: String) -> [FencedTextSegment] {
        var segments: [FencedTextSegment] = []
        var plain: [Substring] = []
        var open: (fence: Fence, language: String?, lines: [Substring])?

        func flushPlain() {
            if !plain.isEmpty { segments.append(.text(plain.joined(separator: "\n"))) }
            plain.removeAll()
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if let block = open {
                if Fence(closing: line, for: block.fence) != nil {
                    segments.append(
                        .code(block.lines.joined(separator: "\n"), language: block.language, isClosed: true))
                    open = nil
                } else {
                    open?.lines.append(Self.dedented(line, by: block.fence.indent))
                }
            } else if let fence = Fence(opening: line) {
                flushPlain()
                open = (fence, fence.language, [])
            } else {
                plain.append(line)
            }
        }
        if let block = open {
            segments.append(.code(block.lines.joined(separator: "\n"), language: block.language, isClosed: false))
        }
        flushPlain()
        return segments
    }

    /// Whether the text holds a fenced code block at all, for callers that render plain text faster.
    public static func containsFence(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { Fence(opening: $0) != nil }
    }

    /// Code lines lose up to the opening fence's own indent, as CommonMark has it.
    private static func dedented(_ line: Substring, by indent: Int) -> Substring {
        var line = line
        var removed = 0
        while removed < indent, line.first == " " {
            line = line.dropFirst()
            removed += 1
        }
        return line
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
