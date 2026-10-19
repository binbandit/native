import Foundation

/// A justfile's public recipes that run without arguments, as `just <recipe>`, with their doc
/// comments.
enum JustfileDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard let file = folder.first(of: ["justfile", "Justfile", ".justfile"]), let text = folder.text(file) else {
            return []
        }
        return recipes(in: text).map {
            ProjectSuggestion.named($0.name, command: "just \($0.name)", source: .justfile, detail: $0.doc)
        }
    }

    struct Recipe: Equatable {
        let name: String
        let doc: String?
    }

    /// The recipes a user can run as `just <name>`: not private (`_name` or `[private]`), and with
    /// no parameter that needs a value.
    static func recipes(in text: String) -> [Recipe] {
        var recipes: [Recipe] = []
        var comment: String?
        var attributes: [String] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                comment = nil
                attributes = []
                continue
            }
            // Recipe bodies and continuation lines are indented.
            guard let first = line.first, !first.isWhitespace else { continue }
            if trimmed.hasPrefix("#") {
                comment = trimmed.hasPrefix("#!") ? nil : trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                continue
            }
            if trimmed.hasPrefix("[") {
                attributes.append(trimmed)
                continue
            }
            defer {
                comment = nil
                attributes = []
            }
            guard let header = header(trimmed) else { continue }
            let isPrivate = header.name.hasPrefix("_") || attributes.contains { $0.contains("private") }
            guard !isPrivate, !header.needsArguments else { continue }
            recipes.append(Recipe(name: header.name, doc: doc(from: attributes) ?? comment))
        }
        return recipes
    }

    private static let keywords: Set = ["set", "alias", "export", "import", "mod", "unexport"]

    /// A recipe's name and whether it needs arguments, from its header line (`test *args: build`).
    private static func header(_ line: String) -> (name: String, needsArguments: Bool)? {
        // Quoted defaults can hold colons (`url="http://x"`), so look for the colon without them.
        let line = withoutQuotedText(line.hasPrefix("@") ? String(line.dropFirst()) : line)
        guard let colon = line.firstIndex(of: ":") else { return nil }
        // `name := value` is a variable.
        if line[colon...].hasPrefix(":=") { return nil }
        let words = line[..<colon].split(whereSeparator: \.isWhitespace).map(String.init)
        guard let name = words.first, !keywords.contains(name),
            name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }),
            name.first?.isNumber == false
        else { return nil }
        // `x`, `$x` and `+x` need a value; `x=default` and `*x` don't.
        let needsArguments = words.dropFirst().contains { word in
            !word.contains("=") && !word.hasPrefix("*")
        }
        return (name, needsArguments)
    }

    /// `[doc("Run the tests")]`.
    private static func doc(from attributes: [String]) -> String? {
        for attribute in attributes {
            guard let start = attribute.range(of: "doc(") else { continue }
            let rest = attribute[start.upperBound...]
            guard let open = rest.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { continue }
            let quote = rest[open]
            let body = rest[rest.index(after: open)...]
            if let close = body.firstIndex(of: quote) { return String(body[..<close]) }
        }
        return nil
    }

    /// Drops quoted defaults (`env="a b"`), so their spaces don't split parameters.
    private static func withoutQuotedText(_ text: String) -> String {
        var result = ""
        var quote: Character?
        for character in text {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" || character == "`" {
                quote = character
                result.append("_")
            } else {
                result.append(character)
            }
        }
        return result
    }
}
