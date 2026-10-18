import Foundation

/// GitHub's suggested changes: a ```` ```suggestion ```` fence in a review comment holds the lines
/// that should replace the commented ones.
public enum SuggestionBlock {
    public enum Segment: Sendable, Hashable {
        case markdown(String)
        /// The replacement lines; empty to delete them.
        case suggestion(String)
    }

    /// The comment split into Markdown and suggestions, in order.
    public static func segments(of body: String) -> [Segment] {
        var segments: [Segment] = []
        var markdown: [Substring] = []
        var suggestion: [Substring]?
        var fence = ""
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var lines = suggestion {
                if trimmed == fence {
                    segments.append(.suggestion(lines.joined(separator: "\n")))
                    suggestion = nil
                } else {
                    lines.append(line)
                    suggestion = lines
                }
            } else if let opening = Self.opening(trimmed) {
                if !markdown.isEmpty { segments.append(.markdown(markdown.joined(separator: "\n"))) }
                markdown = []
                fence = opening
                suggestion = []
            } else {
                markdown.append(line)
            }
        }
        // An unclosed fence is shown as GitHub shows it: as the suggestion so far.
        if let suggestion { segments.append(.suggestion(suggestion.joined(separator: "\n"))) }
        let rest = markdown.joined(separator: "\n")
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.markdown(rest))
        }
        return segments
    }

    /// A suggestion fence around `lines`, to start a comment that proposes an edit.
    public static func fence(_ lines: String) -> String {
        "```suggestion\n\(lines)\n```"
    }

    /// The fence a suggestion opens with (three or more backticks), or `nil` for any other line.
    private static func opening(_ line: String) -> String? {
        let ticks = line.prefix { $0 == "`" }
        guard ticks.count >= 3,
            line.dropFirst(ticks.count).trimmingCharacters(in: .whitespaces) == "suggestion"
        else {
            return nil
        }
        return String(ticks)
    }
}
