import Foundation

/// As much of a tool's output as a detail panel shows: all of it up to a limit, else its start
/// (a file, search results) or its end (a command, where the result and the error are), with a
/// note of what's left out. A panel scrolls, but laying out megabytes of text would stall the
/// transcript; the whole output stays one copy away.
public struct ToolOutputExcerpt: Hashable, Sendable {
    public enum End: Hashable, Sendable {
        case start, end
    }

    public static let maxLines = 400
    public static let maxCharacters = 40_000

    /// The part shown.
    public let text: String
    public let totalLines: Int
    /// Lines shown, whole or cut.
    public let shownLines: Int
    /// Some of the output isn't in `text`.
    public let isTruncated: Bool
    /// Which end of the output `text` is.
    public let keeps: End

    public init(
        _ output: String, keeping end: End, maxLines: Int = Self.maxLines, maxCharacters: Int = Self.maxCharacters
    ) {
        keeps = end
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        totalLines = lines.count
        guard lines.count > maxLines || output.utf8.count > maxCharacters else {
            text = output
            shownLines = lines.count
            isTruncated = false
            return
        }
        var kept: [Substring] = []
        var characters = 0
        var cutLine = false
        for line in end == .start ? Array(lines) : lines.reversed() {
            let room = maxCharacters - characters
            guard kept.count < maxLines, room > 0 else { break }
            // A single enormous line (minified code, a binary dump) is cut rather than dropped.
            if line.count > room {
                kept.append(end == .start ? line.prefix(room) : line.suffix(room))
                cutLine = true
            } else {
                kept.append(line)
            }
            characters += line.count + 1
        }
        if end == .end { kept.reverse() }
        text = kept.joined(separator: "\n")
        shownLines = kept.count
        isTruncated = cutLine || kept.count < lines.count
    }

    /// "Showing the last 400 of 12,345 lines", or nil when it's all there.
    public var note: String? {
        guard isTruncated else { return nil }
        let which = keeps == .start ? "first" : "last"
        guard shownLines < totalLines else { return "Showing the \(which) part of a long line" }
        return "Showing the \(which) \(shownLines.formatted()) of \(totalLines.formatted()) lines"
    }
}
