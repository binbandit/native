import Foundation

/// The line a reviewer ends a checkpoint with: `VERDICT: pass - <note>` or
/// `VERDICT: changes - <summary>`, findings above it. Parsed like a goal's status line: forgiving
/// about decoration, strict about position (one of the last lines) and shape.
public nonisolated struct CheckpointVerdict: Codable, Hashable, Sendable {
    public enum Outcome: String, Codable, Hashable, Sendable {
        case pass, changes
    }

    public var outcome: Outcome
    public var note: String?
    /// The reviewer's reply without the verdict line: its findings.
    public var findings: String

    public init(outcome: Outcome, note: String?, findings: String) {
        self.outcome = outcome
        self.note = note
        self.findings = findings
    }

    public static let protocolLines = """
        VERDICT: pass - <what you checked>
        VERDICT: changes - <the problems, in one line>
        """

    static let searchedLineCount = 6
    private static let decoration = CharacterSet(charactersIn: "*_`>#~•-").union(.whitespaces)
    private static let separators = CharacterSet(charactersIn: "-–—:.,;()*_`").union(.whitespaces)

    public init?(parsing reply: String) {
        var lines = reply.components(separatedBy: .newlines)
        let candidates = lines.indices.reversed().filter { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(Self.searchedLineCount)
        for index in candidates {
            if let (outcome, note) = Self.parseLine(lines[index]) {
                lines.remove(at: index)
                self.init(
                    outcome: outcome, note: note,
                    findings: lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
        }
        return nil
    }

    private static func parseLine(_ line: String) -> (Outcome, String?)? {
        let text = line.trimmingCharacters(in: decoration).lowercased()
        guard text.hasPrefix("verdict") else { return nil }
        let rest = Substring(text.dropFirst("verdict".count)).drop { $0.unicodeScalars.allSatisfy(separators.contains) }
        let outcomes: [(String, Outcome)] = [
            ("pass", .pass), ("passed", .pass), ("changes", .changes), ("changes needed", .changes), ("fail", .changes),
            ("failed", .changes),
        ]
        // Longest first, so "passed" isn't read as "pass" followed by "ed".
        for (word, outcome) in outcomes.sorted(by: { $0.0.count > $1.0.count }) where rest.hasPrefix(word) {
            let after = rest.dropFirst(word.count)
            guard after.first.map({ $0.unicodeScalars.allSatisfy(separators.contains) }) ?? true else { continue }
            // The note keeps the reviewer's own capitalization.
            let original = line.trimmingCharacters(in: decoration)
            let note = String(original.suffix(after.count)).trimmingCharacters(in: separators.union(.whitespaces))
            return (outcome, note.isEmpty ? nil : note)
        }
        return nil
    }
}
