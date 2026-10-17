import Foundation

/// The status line an agent ends a goal turn with: `GOAL: complete - <evidence>`,
/// `GOAL: blocked - <what it needs>` or `GOAL: continuing - <next step>`. Agents follow the format
/// loosely (bold, backticks, synonyms, other dashes), so parsing is forgiving about decoration and
/// strict about position and shape: the marker starts its own line near the end of the reply, the
/// status is followed by a separator or nothing, and the last marker wins. That keeps a restated
/// objective ("Goal: complete the migration") from reading as a report.
public nonisolated struct GoalMarker: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case continuing, blocked, complete
    }

    public var status: Status
    /// The agent's note after the status, if it wrote one.
    public var note: String?

    /// How many non-empty lines from the end a marker may sit. Agents sometimes add a sign-off after
    /// it; a "Goal:" line further up is the agent restating the objective.
    public static let searchedLineCount = 6

    public init(status: Status, note: String?) {
        self.status = status
        self.note = note
    }

    /// The last status line in `reply`, if there is one.
    init?(parsing reply: String) {
        guard let (_, marker) = Self.lastMarker(in: reply) else { return nil }
        self = marker
    }

    /// `reply` without its status line, for handing a step's result to the next step.
    public static func stripping(_ reply: String) -> String {
        var lines = reply.components(separatedBy: .newlines)
        if let (index, _) = lastMarker(in: reply) {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lastMarker(in reply: String) -> (Int, GoalMarker)? {
        let lines = reply.components(separatedBy: .newlines)
        let candidates = lines.indices.reversed()
            .filter { !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
            .prefix(searchedLineCount)
        for index in candidates {
            if let marker = parseLine(lines[index]) {
                return (index, marker)
            }
        }
        return nil
    }

    private static let decoration = CharacterSet(charactersIn: "*_`>#~•").union(.whitespaces)
    private static let separators = CharacterSet(charactersIn: "-–—:.,;()*_`").union(.whitespaces)

    private static func parseLine(_ line: String) -> GoalMarker? {
        let leading = decoration.union(CharacterSet(charactersIn: "-"))
        var rest = Substring(line.trimmingCharacters(in: .whitespaces)).drop { $0.unicodeScalars.allSatisfy(leading.contains) }
        guard rest.lowercased().hasPrefix("goal") else { return nil }
        rest = rest.dropFirst(4)
        // "GOAL STATUS: complete" is a common rewording.
        if rest.lowercased().hasPrefix(" status") {
            rest = rest.dropFirst(7)
        }
        rest = rest.drop { $0 == " " || $0 == "*" || $0 == "_" }
        guard let colon = rest.first, colon == ":" || colon == "：" else { return nil }
        // Only leading decoration goes: a trailing ">" may close a placeholder that has to be seen.
        let body = String(rest.dropFirst().drop { $0.unicodeScalars.allSatisfy(decoration.contains) })
        let lowered = body.lowercased()
        guard let match = statusWords.first(where: { lowered.hasPrefix($0.word) }) else { return nil }
        let remainder = String(body.dropFirst(match.word.count))
        // The status ends at a separator or the end of the line, never mid-sentence.
        let afterSpaces = remainder.drop { $0 == " " }
        if let next = afterSpaces.first, !next.unicodeScalars.allSatisfy(separators.contains) {
            return nil
        }
        let note = closingEmphasisRemoved(from: remainder.drop { $0.unicodeScalars.allSatisfy(separators.contains) })
        // An agent echoing the instructions writes the placeholder, not a note; that's no report.
        if note.hasPrefix("<"), note.hasSuffix(">") {
            return nil
        }
        return GoalMarker(status: match.status, note: note.isEmpty ? nil : note)
    }

    /// Drops the end of emphasis that opened before the marker (`**GOAL: done - x**`, `` `GOAL: done - x` ``)
    /// while keeping the note's own punctuation.
    private static func closingEmphasisRemoved(from note: Substring) -> String {
        var note = Substring(note.trimmingCharacters(in: .whitespaces))
        while note.hasSuffix("**") || note.hasSuffix("__") {
            note = note.dropLast(2)
        }
        if note.hasSuffix("`"), note.count(where: { $0 == "`" }) % 2 == 1 {
            note = note.dropLast()
        }
        return note.trimmingCharacters(in: .whitespaces)
    }

    /// Longer phrases first, so "not complete" never reads as "complete".
    private static let statusWords: [(word: String, status: Status)] = [
        ("not complete", .continuing), ("incomplete", .continuing), ("in progress", .continuing),
        ("in-progress", .continuing), ("continuing", .continuing), ("continue", .continuing),
        ("ongoing", .continuing), ("working", .continuing),
        ("blocked", .blocked), ("stuck", .blocked), ("needs input", .blocked), ("needs user", .blocked),
        ("completed", .complete), ("complete", .complete), ("done", .complete), ("achieved", .complete),
        ("met", .complete), ("finished", .complete),
    ]
}
