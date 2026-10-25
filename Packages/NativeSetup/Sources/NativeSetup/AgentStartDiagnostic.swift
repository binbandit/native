import Foundation

/// The place a failed start points at, in the agent's own words: a compiler-style
/// `path:line:column: message`, the way agents report a settings file they can't read. Output that
/// names no file makes no diagnostic, so Native claims nothing it wasn't told.
public struct AgentStartDiagnostic: Equatable, Sendable {
    /// The file as the agent named it: absolute, on the machine the agent runs on.
    public let path: String
    /// 1-based, like the agent's own report.
    public let line: Int
    public let column: Int
    /// What the agent says is wrong there: "unknown variant `sometimes`, expected one of …".
    public let message: String

    public init(path: String, line: Int, column: Int, message: String) {
        self.path = path
        self.line = line
        self.column = column
        self.message = message
    }

    /// The first diagnostic in `output`, if any line of it has one.
    public init?(output: String) {
        let pattern = /(\/[^:\n]+):(\d+):(\d+):\s+(\S[^\n]*)/
        guard let match = output.firstMatch(of: pattern), let line = Int(match.2), let column = Int(match.3),
            line > 0, column > 0
        else { return nil }
        self.init(path: String(match.1), line: line, column: column, message: String(match.4))
    }

    public var fileName: String {
        URL(filePath: path).lastPathComponent
    }

    /// A change Native can offer for the line: a value the agent doesn't know, close to exactly one
    /// it lists ("xhigh" for `minimal`, `low`, `medium`, `high`). Nil when no single value is close.
    public var fixIt: AgentStartFixIt? {
        AgentStartFixIt(message: message)
    }

    /// The line the agent stopped at and the one before it, numbered, from the file's contents.
    /// Lines that look like they hold a credential show their key only.
    public func excerpt(of contents: String) -> [SourceLine] {
        let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard line <= lines.count else { return [] }
        return (max(line - 1, 1)...line).map { number in
            SourceLine(number: number, text: String(lines[number - 1]))
        }
    }

    /// One numbered line of the file. A credential's value is never kept: `text` stops at its key.
    public struct SourceLine: Equatable, Sendable, Identifiable {
        public let number: Int
        public let text: String
        public let isRedacted: Bool

        public var id: Int { number }

        init(number: Int, text: String) {
            self.number = number
            if let key = Self.credentialKey(in: text) {
                self.text = key
                isRedacted = true
            } else {
                self.text = text
                isRedacted = false
            }
        }

        public init(number: Int, text: String, isRedacted: Bool) {
            self.number = number
            self.text = text
            self.isRedacted = isRedacted
        }

        /// The `key =` (or `"key":`) part of a line whose key names a credential.
        private static func credentialKey(in text: String) -> String? {
            guard let separator = text.firstIndex(where: { $0 == "=" || $0 == ":" }) else { return nil }
            let key = text[..<separator].lowercased()
            let words = ["token", "secret", "password", "passwd", "key", "auth", "bearer", "credential", "cookie"]
            guard words.contains(where: key.contains) else { return nil }
            return String(text[...separator])
        }
    }
}

/// Changes one value the agent rejected to the closest one it accepts.
public struct AgentStartFixIt: Equatable, Sendable {
    public let original: String
    public let replacement: String

    public init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }

    /// Reads serde's wording, which agents written in Rust share: "unknown variant `xhigh`,
    /// expected one of `minimal`, `low`, `medium`, `high`".
    init?(message: String) {
        guard let match = message.firstMatch(of: /unknown variant `([^`]+)`, expected (.+)/) else { return nil }
        let original = String(match.1)
        let candidates = match.2.matches(of: /`([^`]+)`/).map { String($0.1) }
        let ranked = candidates.map { ($0, Self.distance(original.lowercased(), $0.lowercased())) }
            .sorted { $0.1 < $1.1 }
        guard let best = ranked.first, best.1 <= max(1, original.count / 3),
            ranked.dropFirst().first?.1 != best.1
        else { return nil }
        self.init(original: original, replacement: best.0)
    }

    /// `contents` with the value on the diagnostic's line replaced, or nil when that line no longer
    /// holds it (the file changed after the agent read it). Everything else stays byte for byte.
    public func apply(to contents: String, at diagnostic: AgentStartDiagnostic) -> String? {
        let lines = contents.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard diagnostic.line <= lines.count else { return nil }
        let line = lines[diagnostic.line - 1]
        let quoted = ["\"\(original)\"", "'\(original)'"]
        let found = quoted.flatMap { line.ranges(of: $0) }
        // The agent's column points at the value; fall back to the only quoted copy on the line.
        let column = line.index(line.startIndex, offsetBy: diagnostic.column - 1, limitedBy: line.endIndex)
        guard let range = found.first(where: { $0.lowerBound == column }) ?? (found.count == 1 ? found.first : nil)
        else { return nil }
        let value = contents.index(after: range.lowerBound)..<contents.index(before: range.upperBound)
        return contents.replacingCharacters(in: value, with: replacement)
    }

    /// Edits to turn one word into the other, a swap of neighbours counting as one: "hgih" is one
    /// from "high".
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }
}
