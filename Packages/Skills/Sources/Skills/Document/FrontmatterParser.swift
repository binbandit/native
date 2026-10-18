import Foundation

/// One frontmatter value, as far as skills use YAML.
enum FrontmatterValue: Hashable, Sendable {
    case scalar(String)
    case list([String])
    case map([String: String])

    var string: String? {
        if case .scalar(let value) = self { value } else { nil }
    }
}

/// The YAML subset SKILL.md frontmatter uses: `key: value` pairs whose values are plain or quoted
/// scalars, `|` and `>` block scalars, lists (block or `[a, b]`) and one level of nested map
/// (`metadata:`). Anything else is reported rather than guessed at, so a malformed SKILL.md shows
/// what's wrong with it.
enum FrontmatterParser {
    struct Failure: Error, Hashable {
        /// 1-based, counting the opening `---` as line 1, like an editor would.
        let line: Int
        let reason: String
    }

    /// The frontmatter's lines and the body after it; nil when the text doesn't open with `---`.
    static func split(_ text: String) -> (yaml: [String], body: String)? {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        if let first = lines.first, first.hasPrefix("\u{FEFF}") { lines[0] = String(first.dropFirst()) }
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }
        return (Array(lines[1..<end]), lines[(end + 1)...].joined(separator: "\n"))
    }

    static func parse(_ lines: [String]) throws(Failure) -> [(key: String, value: FrontmatterValue)] {
        var entries: [(key: String, value: FrontmatterValue)] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                index += 1
                continue
            }
            guard !isIndented(line) else {
                throw Failure(line: index + 2, reason: "It's indented, but nothing above it takes a nested value.")
            }
            guard let colon = keySeparator(in: line) else {
                throw Failure(line: index + 2, reason: "It isn't a `key: value` line.")
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let rest = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            index += 1
            var block: [String] = []
            while index < lines.count {
                let next = lines[index]
                let continues =
                    next.trimmingCharacters(in: .whitespaces).isEmpty || isIndented(next)
                    || (rest.isEmpty && next.hasPrefix("- "))
                guard continues else { break }
                block.append(next)
                index += 1
            }
            while block.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { block.removeLast() }
            entries.append((key, try value(rest, block: block, line: index + 1)))
        }
        return entries
    }

    private static func value(_ rest: String, block: [String], line: Int) throws(Failure) -> FrontmatterValue {
        if let indicator = rest.first, indicator == "|" || indicator == ">" {
            return .scalar(blockScalar(block, folded: indicator == ">"))
        }
        if rest.hasPrefix("[") {
            guard rest.hasSuffix("]") else { throw Failure(line: line, reason: "A `[` list isn't closed.") }
            return .list(splitFlow(String(rest.dropFirst().dropLast())).map(unquote))
        }
        if rest.hasPrefix("{") {
            guard rest.hasSuffix("}") else { throw Failure(line: line, reason: "A `{` map isn't closed.") }
            var map: [String: String] = [:]
            for pair in splitFlow(String(rest.dropFirst().dropLast())) {
                guard let colon = keySeparator(in: pair) else { continue }
                map[pair[..<colon].trimmingCharacters(in: .whitespaces)] = unquote(
                    String(pair[pair.index(after: colon)...]))
            }
            return .map(map)
        }
        guard rest.isEmpty || hasCommentOnly(rest) else {
            // A scalar, possibly continued on indented lines (YAML folds them with spaces).
            let continuation = block.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return .scalar(unquote(([stripComment(rest)] + continuation).joined(separator: " ")))
        }
        let items = block.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = items.first else { return .scalar("") }
        if first.trimmingCharacters(in: .whitespaces).hasPrefix("- ") || first.trimmingCharacters(in: .whitespaces) == "-" {
            return .list(listItems(items))
        }
        var map: [String: String] = [:]
        let indent = indentation(of: first)
        var current: (key: String, parts: [String])?
        for item in items {
            if indentation(of: item) == indent, let colon = keySeparator(in: item) {
                if let current { map[current.key] = unquote(current.parts.joined(separator: " ")) }
                let value = String(item[item.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                current = (item[..<colon].trimmingCharacters(in: .whitespaces), value.isEmpty ? [] : [value])
            } else if indentation(of: item) > indent, current != nil {
                current?.parts.append(item.trimmingCharacters(in: .whitespaces))
            } else {
                throw Failure(line: line, reason: "A nested line isn't `key: value`.")
            }
        }
        if let current { map[current.key] = unquote(current.parts.joined(separator: " ")) }
        return .map(map)
    }

    private static func listItems(_ lines: [String]) -> [String] {
        var items: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                items.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
            } else if !items.isEmpty {
                items[items.count - 1] += " " + trimmed
            }
        }
        return items.map(unquote)
    }

    private static func blockScalar(_ lines: [String], folded: Bool) -> String {
        let indent = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map(indentation).min() ?? 0
        let content = lines.map { $0.count >= indent ? String($0.dropFirst(indent)) : "" }
        guard folded else { return content.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
        // Folded: lines join with spaces, and a blank line is a paragraph break.
        return content.split(separator: "", omittingEmptySubsequences: false).map { $0.joined(separator: " ") }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The colon that ends a key: the first one followed by a space or the end of the line,
    /// outside quotes, so `url: https://x` splits after `url`.
    private static func keySeparator(in line: String) -> String.Index? {
        var quote: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == ":" {
                let next = line.index(after: index)
                if next == line.endIndex || line[next] == " " || line[next] == "\t" {
                    return index == line.startIndex ? nil : index
                }
            }
            index = line.index(after: index)
        }
        return nil
    }

    private static func splitFlow(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
                current.append(character)
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func unquote(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            var result = ""
            var escaping = false
            for character in text.dropFirst().dropLast() {
                if escaping {
                    switch character {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    default: result.append(character)
                    }
                    escaping = false
                } else if character == "\\" {
                    escaping = true
                } else {
                    result.append(character)
                }
            }
            return result
        }
        if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return stripComment(text)
    }

    private static func stripComment(_ text: String) -> String {
        guard !text.hasPrefix("\""), !text.hasPrefix("'"), let range = text.range(of: " #") else { return text }
        return text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
    }

    private static func hasCommentOnly(_ text: String) -> Bool {
        text.hasPrefix("#")
    }

    private static func isIndented(_ line: String) -> Bool {
        line.first == " " || line.first == "\t"
    }

    private static func indentation(of line: String) -> Int {
        line.prefix { $0 == " " || $0 == "\t" }.count
    }
}
