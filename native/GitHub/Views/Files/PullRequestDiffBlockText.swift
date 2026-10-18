import CodeThemes
import GitHub
import SwiftUI

/// A run of diff lines as two texts, the gutter (both line numbers and the change marker) and the
/// code, so a block lays out as one text each instead of a view per line: what keeps scrolling a
/// pull request with thousands of changed lines smooth. Lines don't wrap, so every line has the
/// same height and line `i` sits at `i × height`; a line longer than the pane is cut off with a
/// "…" that opens it.
struct PullRequestDiffBlockText {
    let gutter: AttributedString
    let code: AttributedString
    let kinds: [DiffHunk.Line.Kind]
    /// Lines (offsets in the block) cut off at the pane edge.
    let cutOff: Set<Int>
    /// The code as plain text, for accessibility: resolving the colored text for VoiceOver costs
    /// far more than reading this.
    let plain: String

    /// Minified lines (bundles, lockfiles) show their start: their diff is behind "Load Diff", and
    /// laying out the whole of one costs frames.
    static let minifiedLineLength = 1_000
    static let minifiedDisplayLength = 400

    /// - Parameters:
    ///   - highlighted: The hunk's lines as code segments, when highlighting has finished.
    ///   - numberWidth: Digits in the largest line number of the file, so gutters line up.
    ///   - columns: Characters that fit beside the gutter; longer lines are cut off with "…".
    init(
        lines: ArraySlice<DiffHunk.Line>, highlighted: [[CodeSegment]]?, colors: DSCodeColors, numberWidth: Int,
        columns: Int
    ) {
        var gutter = AttributedString()
        var code = AttributedString()
        var kinds: [DiffHunk.Line.Kind] = []
        var cutOff: Set<Int> = []
        for index in lines.indices {
            let line = lines[index]
            if !kinds.isEmpty {
                gutter += AttributedString("\n")
                code += AttributedString("\n")
            }
            gutter += Self.gutter(line, width: numberWidth)
            var text = Self.code(
                line, highlighted: highlighted.flatMap { $0.indices.contains(index) ? $0[index] : nil }, colors: colors)
            if text.characters.count > columns, columns > 2 {
                let end = text.characters.index(text.startIndex, offsetBy: columns - 2)
                text = AttributedString(text[text.startIndex..<end]) + Self.cutOffMarker
                cutOff.insert(kinds.count)
            }
            code += text
            kinds.append(line.kind)
        }
        self.gutter = gutter
        self.code = code
        self.kinds = kinds
        self.cutOff = cutOff
        plain = lines.map(\.text).joined(separator: "\n")
    }

    /// "…" on a tinted chip where a cut-off line ends, so it reads as something to click rather
    /// than as part of the code.
    static var cutOffMarker: AttributedString {
        var marker = AttributedString("…")
        marker.foregroundColor = .dsAccentText
        marker.backgroundColor = .dsAccentSubtle
        return AttributedString(" ") + marker
    }

    /// Both line numbers and the change marker, as the gutter shows them.
    static func gutter(_ line: DiffHunk.Line, width: Int) -> AttributedString {
        func number(_ value: Int?) -> String {
            let text = value.map(String.init) ?? ""
            return String(repeating: " ", count: max(width - text.count, 0)) + text
        }
        var numbers = AttributedString(" \(number(line.oldNumber))  \(number(line.newNumber)) ")
        numbers.foregroundColor = .dsTextTertiary
        var marker: AttributedString
        switch line.kind {
        case .added:
            marker = AttributedString(" + ")
            marker.foregroundColor = .dsSuccess
        case .removed:
            marker = AttributedString(" - ")
            marker.foregroundColor = .dsDanger
        case .context, .noNewline:
            marker = AttributedString("   ")
        }
        return numbers + marker
    }

    /// Characters the gutter takes, for working out how much code fits beside it.
    static func gutterColumns(numberWidth: Int) -> Int {
        numberWidth * 2 + 7
    }

    /// A line's code, highlighted when it can be, with tabs as four spaces so columns line up.
    static func code(_ line: DiffHunk.Line, highlighted: [CodeSegment]?, colors: DSCodeColors) -> AttributedString {
        if line.kind == .noNewline {
            var text = AttributedString(line.text)
            text.foregroundColor = .dsTextTertiary
            return text
        }
        let segments = highlighted?.map { CodeSegment($0.text.replacingOccurrences(of: "\t", with: "    "), $0.role) }
        var text = segments.map(colors.text) ?? AttributedString(line.text.replacingOccurrences(of: "\t", with: "    "))
        guard line.text.utf8.count > minifiedLineLength else { return text }
        let end = text.characters.index(
            text.startIndex, offsetBy: min(minifiedDisplayLength, text.characters.count))
        text = AttributedString(text[text.startIndex..<end])
        var more = AttributedString("  … \(line.text.count - minifiedDisplayLength) more characters")
        more.foregroundColor = .dsTextTertiary
        return text + more
    }
}
