import Foundation

extension String {
    /// The last segment of a path, which is what a row names: `/a/b/ToolRow.swift` is
    /// `ToolRow.swift`. A trailing slash is ignored; a bare `/` or `.` stays as it is.
    var fileName: String {
        let trimmed = hasSuffix("/") && count > 1 ? String(dropLast()) : self
        guard let slash = trimmed.lastIndex(of: "/"), slash != trimmed.index(before: trimmed.endIndex) else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: slash)...])
    }

    /// A URL's host without `www.` (`docs.swift.org`), or the text itself when it isn't one.
    var urlHost: String {
        guard let host = URL(string: self)?.host(), !host.isEmpty else { return self }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The agent's title, unless it's a placeholder that says nothing about the call ("Terminal",
    /// "Tool call", Claude Code's "Read File" and "Preparing file…" before its input arrives), or
    /// with the "completed" some agents add at the end taken off.
    var meaningfulTitle: String? {
        var title = trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" completed", " complete"] where title.lowercased().hasSuffix(suffix) {
            title = String(title.dropLast(suffix.count))
        }
        let placeholders: Set<String> = [
            "", "tool", "tool call", "terminal", "task", "read file", "preparing file…", "preparing file...",
        ]
        return placeholders.contains(title.lowercased()) ? nil : title
    }

    /// Single quotes around a value read as double ones: `Search for 'def'` is `Search for "def"`.
    var unquoted: String {
        replacingOccurrences(of: "'", with: "\"")
    }

    /// `fetch_pull-requestDetails` is `fetch pull request Details`.
    var humanized: String {
        var words: [String] = []
        var current = ""
        for character in self {
            if character == "_" || character == "-" || character == " " {
                if !current.isEmpty { words.append(current) }
                current = ""
            } else if character.isUppercase, let last = current.last, last.isLowercase || last.isNumber {
                words.append(current)
                current = String(character)
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }

    /// `search_issues` is `Search Issues`; acronyms stay upper case.
    var titleCased: String {
        humanized.split(separator: " ").map { word in
            word.allSatisfy { $0.isUppercase || $0.isNumber }
                ? String(word) : word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }
        .joined(separator: " ")
    }

    /// `setup_status` is `Setup status`; acronyms stay upper case.
    var sentenceCased: String {
        humanized.split(separator: " ").enumerated().map { index, word in
            if word.allSatisfy({ $0.isUppercase || $0.isNumber }) { return String(word) }
            return index == 0 ? word.prefix(1).uppercased() + word.dropFirst().lowercased() : word.lowercased()
        }
        .joined(separator: " ")
    }

    func dropping(prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }

    func dropping(suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
