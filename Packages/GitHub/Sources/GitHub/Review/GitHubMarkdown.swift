import Foundation

/// Markdown as GitHub shows it, where that differs from what's written.
public enum GitHubMarkdown {
    /// What a comment shows: HTML comments dropped, and the HTML GitHub renders (disclosures, links,
    /// pictures, `<sup>` and the like) turned into Markdown or dropped, so it doesn't print as tags.
    public static func displayed(_ markdown: String) -> String {
        removingInlineHTML(removingDisclosureTags(removingComments(markdown)))
    }

    /// Inline HTML outside code, as bots' footers use it: links become Markdown links, pictures and
    /// images go (with a link left empty by one), and formatting tags go but keep their text.
    static func removingInlineHTML(_ markdown: String) -> String {
        guard markdown.contains("<") || markdown.contains("&nbsp;") else { return markdown }
        var fence: Substring?
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.drop { $0 == " " }
            if let open = fence {
                if trimmed.hasPrefix(open) { fence = nil }
                return String(line)
            }
            if let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                fence = Substring(marker)
                return String(line)
            }
            // Code spans sit between backticks: every other piece.
            return line.split(separator: "`", omittingEmptySubsequences: false).enumerated()
                .map { $0.offset.isMultiple(of: 2) ? markdownForHTML(String($0.element)) : String($0.element) }
                .joined(separator: "`")
        }
        return lines.joined(separator: "\n")
    }

    private static func markdownForHTML(_ text: String) -> String {
        guard text.contains("<") || text.contains("&nbsp;") else { return text }
        let options: String.CompareOptions = [.regularExpression, .caseInsensitive]
        var text = text.replacingOccurrences(of: #"<picture\b[^>]*>.*?</picture>"#, with: "", options: options)
        text = text.replacingOccurrences(of: #"<img\b[^>]*>"#, with: "", options: options)
        text = text.replacingOccurrences(of: #"<a\b[^>]*>\s*</a>"#, with: "", options: options)
        text = text.replacingOccurrences(
            of: #"<a\b[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#, with: "[$2]($1)", options: options)
        text = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: options)
        text = text.replacingOccurrences(
            of: #"</?(?:a|sup|sub|source|span|div|p|b|i|em|strong|small|ins|del|center|kbd)\b[^>]*>"#, with: "",
            options: options)
        return text.replacingOccurrences(of: "&nbsp;", with: " ")
    }

    /// `<summary>Title</summary>` becomes a bold line; `<details>` and `</details>` go.
    static func removingDisclosureTags(_ markdown: String) -> String {
        guard markdown.localizedCaseInsensitiveContains("<details") else { return markdown }
        var text = markdown.replacingOccurrences(
            of: #"<summary>\s*(.*?)\s*</summary>"#, with: "**$1**\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(
            of: #"</?details[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        return text.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Drops HTML comments (`<!-- … -->`), which GitHub hides: pull request templates are full of
    /// them. Code blocks keep theirs, and the blank lines a comment leaves collapse.
    public static func removingComments(_ markdown: String) -> String {
        guard markdown.contains("<!--") else { return markdown }
        var output: [Substring] = []
        var fence: Substring?
        var inComment = false
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.drop { $0 == " " }
            if let open = fence {
                output.append(line)
                if trimmed.hasPrefix(open) { fence = nil }
                continue
            }
            if !inComment, let marker = ["```", "~~~"].first(where: { trimmed.hasPrefix($0) }) {
                fence = Substring(marker)
                output.append(line)
                continue
            }
            var kept = ""
            var rest = line[...]
            while !rest.isEmpty {
                if inComment {
                    guard let end = rest.range(of: "-->") else {
                        rest = rest[rest.endIndex...]
                        break
                    }
                    inComment = false
                    rest = rest[end.upperBound...]
                } else if let start = rest.range(of: "<!--") {
                    kept += rest[..<start.lowerBound]
                    inComment = true
                    rest = rest[start.upperBound...]
                } else {
                    kept += rest
                    rest = rest[rest.endIndex...]
                }
            }
            output.append(Substring(kept))
        }
        // Collapse the runs of blank lines removed comments leave behind.
        var collapsed: [Substring] = []
        for line in output {
            let isBlank = line.allSatisfy(\.isWhitespace)
            if isBlank, collapsed.last.map({ $0.allSatisfy(\.isWhitespace) }) ?? true { continue }
            collapsed.append(isBlank ? "" : line)
        }
        return collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
