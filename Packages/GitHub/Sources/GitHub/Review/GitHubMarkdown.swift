import Foundation

/// Markdown as GitHub shows it, where that differs from what's written.
public enum GitHubMarkdown {
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
