import Foundation

/// One `@@` section of a unified diff, as GitHub's `patch` for a file holds them, with every line
/// numbered on the side it belongs to.
public struct DiffHunk: Sendable, Hashable, Identifiable {
    public struct Line: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case context, added, removed
            /// `\ No newline at end of file`.
            case noNewline
        }

        public var kind: Kind
        /// The text without its leading `+`, `-` or space.
        public var text: String
        public var oldNumber: Int?
        public var newNumber: Int?

        /// Where a review comment on this line attaches: removed lines on the base side, others on
        /// the head side.
        public var anchor: (side: DiffSide, line: Int)? {
            switch kind {
            case .removed: oldNumber.map { (.left, $0) }
            case .added, .context: newNumber.map { (.right, $0) }
            case .noNewline: nil
            }
        }
    }

    /// `@@ -1,13 +1,14 @@`.
    public var header: String
    /// What follows the header: often the enclosing function.
    public var section: String?
    public var oldStart: Int
    public var newStart: Int
    public var lines: [Line]

    public var id: String { header + "@\(newStart)" }

    /// The hunks of a file's patch. A malformed header ends the parse, keeping what came before.
    public static func parse(_ patch: String) -> [DiffHunk] {
        var hunks: [DiffHunk] = []
        var oldLine = 0
        var newLine = 0
        for raw in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            if line.hasPrefix("@@") {
                guard let header = Header(line) else { break }
                hunks.append(
                    DiffHunk(
                        header: header.text, section: header.section, oldStart: header.oldStart,
                        newStart: header.newStart, lines: []))
                oldLine = header.oldStart
                newLine = header.newStart
                continue
            }
            guard !hunks.isEmpty else { continue }
            let text = String(line.dropFirst())
            switch line.first {
            case "+":
                hunks[hunks.count - 1].lines.append(
                    Line(kind: .added, text: text, oldNumber: nil, newNumber: newLine))
                newLine += 1
            case "-":
                hunks[hunks.count - 1].lines.append(
                    Line(kind: .removed, text: text, oldNumber: oldLine, newNumber: nil))
                oldLine += 1
            case "\\":
                hunks[hunks.count - 1].lines.append(
                    Line(kind: .noNewline, text: String(line), oldNumber: nil, newNumber: nil))
            case " ":
                hunks[hunks.count - 1].lines.append(
                    Line(kind: .context, text: text, oldNumber: oldLine, newNumber: newLine))
                oldLine += 1
                newLine += 1
            default:
                // A trailing empty line after the last hunk isn't part of the diff.
                continue
            }
        }
        return hunks
    }

    /// The index of the line a comment on `side` at `line` attaches to.
    public func index(side: DiffSide, line: Int) -> Int? {
        lines.firstIndex { $0.anchor?.side == side && $0.anchor?.line == line }
    }

    /// The hunk's lines from `start` through `end` as diff text, for prompts and suggestions.
    public func excerpt(_ range: ClosedRange<Int>) -> String {
        lines[range.clamped(to: lines.indices.lowerBound...max(lines.indices.upperBound - 1, 0))]
            .map { line in
                switch line.kind {
                case .added: "+" + line.text
                case .removed: "-" + line.text
                case .context: " " + line.text
                case .noNewline: line.text
                }
            }
            .joined(separator: "\n")
    }

    /// `@@ -oldStart,oldCount +newStart,newCount @@ section`.
    private struct Header {
        let text: String
        let section: String?
        let oldStart: Int
        let newStart: Int

        init?(_ line: Substring) {
            let parts = line.split(separator: "@@", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2 else { return nil }
            let ranges = parts[1].split(separator: " ")
            guard ranges.count >= 2, ranges[0].hasPrefix("-"), ranges[1].hasPrefix("+"),
                let oldStart = Int(ranges[0].dropFirst().split(separator: ",")[0]),
                let newStart = Int(ranges[1].dropFirst().split(separator: ",")[0])
            else { return nil }
            let section = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            text = "@@" + parts[1] + "@@"
            self.section = section.isEmpty ? nil : section
            self.oldStart = oldStart
            self.newStart = newStart
        }
    }
}
