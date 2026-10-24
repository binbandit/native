import Foundation

/// A small, safe excerpt for choosing colors, never a second transcript of the user's work.
public struct SpecimenLine: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let number: Int?
        public let text: String

        public init(number: Int?, text: String) {
            self.number = number
            self.text = text
        }
    }

    public struct Candidate: Sendable {
        public let file: String
        public let project: String
        public let language: CodeLanguage
        public let deleted: [Line]
        public let added: [Line]

        public init(file: String, project: String, language: CodeLanguage, deleted: [Line], added: [Line]) {
            self.file = file
            self.project = project
            self.language = language
            self.deleted = deleted
            self.added = added
        }
    }

    public let file: String
    public let project: String
    public let language: CodeLanguage
    public let deleted: [Line]
    public let added: [Line]
    public let isSample: Bool

    /// Candidates are newest first. Only a strictly richer line replaces the current choice.
    public static func choose(from candidates: [Candidate], recentLanguages: [CodeLanguage] = []) -> Self {
        var best: (candidate: Candidate, index: Int, score: Int)?
        for candidate in candidates {
            guard isSafe(candidate.file), isSafe(candidate.project) else { continue }
            for (index, line) in candidate.added.enumerated() {
                guard accepts(line.text) else { continue }
                let roles = Set(CodeHighlighter.segments(line.text, language: candidate.language).map(\.role))
                let score = roles.intersection(scoredRoles).count
                guard score >= 4, score > (best?.score ?? 0) else { continue }
                best = (candidate, index, score)
            }
        }
        guard let best else { return sample(language: preferredLanguage(recentLanguages)) }
        let candidate = best.candidate
        let start = max(0, best.index - 1)
        let added = candidate.added.dropFirst(start).prefix(2).filter { accepts($0.text) }
        let deleted = candidate.deleted.dropFirst(min(start, max(0, candidate.deleted.count - 2)))
            .prefix(2).filter { accepts($0.text) }
        // An unsafe deleted line must never sneak into a safe added line's preview.
        let before =
            deleted.isEmpty
            ? added.map { Line(number: nil, text: String($0.text.dropLast())) } : Array(deleted)
        return Self(
            file: candidate.file, project: candidate.project, language: candidate.language,
            deleted: before, added: Array(added), isSample: false)
    }

    /// Splits a file's changes into contiguous hunks, retaining the real line numbers and indentation.
    /// Bounded before diffing so opening Settings cannot become an unbounded file comparison.
    public static func candidates(file: String, project: String, before: String?, after: String) -> [Candidate] {
        guard let language = CodeLanguage.forPath(file), after.utf8.count <= 100_000,
            (before?.utf8.count ?? 0) <= 100_000
        else { return [] }
        let old = sourceLines(before ?? "")
        let new = sourceLines(after)
        guard old.count <= 2_000, new.count <= 2_000 else { return [] }
        let difference = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var result: [Candidate] = []
        var a = 0, b = 0
        while a < old.count || b < new.count {
            var deleted: [Line] = [], added: [Line] = []
            while a < old.count, removed.contains(a) {
                deleted.append(Line(number: a + 1, text: old[a])); a += 1
            }
            while b < new.count, inserted.contains(b) {
                added.append(Line(number: b + 1, text: new[b])); b += 1
            }
            if !added.isEmpty {
                result.append(
                    Candidate(file: file, project: project, language: language, deleted: deleted, added: added))
            }
            if deleted.isEmpty && added.isEmpty { a += 1; b += 1 }
        }
        return result
    }

    private static func sourceLines(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // A final line terminator does not add a blank line to a diff.
        if normalized.hasSuffix("\n") { lines.removeLast() }
        return lines
    }

    public static func isSafe(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline), !hasLongLiteral(text) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return !secretPatterns.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    // A quote of another kind inside a literal must not split it into apparently safe pieces.
    private static func hasLongLiteral(_ text: String) -> Bool {
        var delimiter: Character?
        var length = 0
        var escaped = false
        for character in text {
            if let quote = delimiter {
                if escaped {
                    escaped = false
                    length += 1
                } else if character == "\\" {
                    escaped = true
                    length += 1
                } else if character == quote {
                    delimiter = nil
                    length = 0
                } else {
                    length += 1
                }
                if length > 32 { return true }
            } else if character == "\"" || character == "'" || character == "`" {
                delimiter = character
                length = 0
            }
        }
        return false
    }

    private static func accepts(_ text: String) -> Bool {
        text.drop(while: { $0 == " " || $0 == "\t" }).count <= 64 && isSafe(text)
    }

    private static let scoredRoles: Set<CodeTokenRole> = [
        .keyword, .string, .constant, .function, .type, .comment, .operator,
    ]
    private static let secretPatterns: [NSRegularExpression] = [
        #"(?i)(api[_-]?key|token|secret|passw|bearer|authorization)"#,
        #"[A-Za-z0-9+/=_-]{24,}"#,
        #"[a-zA-Z][a-zA-Z0-9+.-]*://[^\s/]+@"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    private static func preferredLanguage(_ languages: [CodeLanguage]) -> CodeLanguage {
        let supported: [CodeLanguage] = [.typeScript, .swift, .python, .go, .rust]
        let recent = languages.filter { supported.contains($0) }
        var winner = recent.first ?? .typeScript
        for language in recent where recent.filter({ $0 == language }).count > recent.filter({ $0 == winner }).count {
            winner = language
        }
        return winner
    }
}
