import CodeThemes
import GitHub
import SwiftUI

/// A run of diff lines as two texts for the platform's text view, the gutter (both line numbers
/// and the change marker) and the code, so a block is two text views instead of a view per line:
/// what keeps scrolling a pull request with thousands of changed lines smooth. Lines don't wrap and
/// all have the same height, so line `i` sits at `i × lineHeight`; a line longer than the pane is
/// cut off with a "…" link that opens it.
struct PullRequestDiffBlockText {
    let gutter: NSAttributedString
    let code: NSAttributedString
    let kinds: [DiffHunk.Line.Kind]
    /// Lines (offsets in the block) cut off at the pane edge.
    let cutOff: Set<Int>

    /// Minified lines (bundles, lockfiles) show their start: their diff is behind "Load Diff", and
    /// laying out the whole of one costs frames.
    static let minifiedLineLength = 1_000
    static let minifiedDisplayLength = 400
    /// The "…" on a cut-off line links here, followed by the line's offset in the block.
    static let expandLinkPrefix = "native-diff-line:"

    /// - Parameters:
    ///   - highlighted: The hunk's lines as code segments, when highlighting has finished.
    ///   - numberWidth: Digits in the largest line number of the file, so gutters line up.
    ///   - columns: Characters that fit beside the gutter; longer lines are cut off with "…".
    ///   - font: The diff's code font; every line is `lineHeight` tall.
    init(
        lines: ArraySlice<DiffHunk.Line>, highlighted: [[CodeSegment]]?, colors: DSCodeColors, numberWidth: Int,
        columns: Int, font: DSPlatformFont, lineHeight: CGFloat, environment: EnvironmentValues
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
            let text = Self.code(
                line, highlighted: highlighted.flatMap { $0.indices.contains(index) ? $0[index] : nil }, colors: colors)
            if var cut = Self.cutOff(text, columns: columns) {
                let marker = cut.characters.index(before: cut.endIndex)
                cut[marker..<cut.endIndex].link = URL(string: Self.expandLinkPrefix + String(kinds.count))
                code += cut
                cutOff.insert(kinds.count)
            } else {
                code += text
            }
            kinds.append(line.kind)
        }
        self.gutter = PlatformCodeText.attributed(gutter, font: font, lineHeight: lineHeight, in: environment)
        self.code = PlatformCodeText.attributed(code, font: font, lineHeight: lineHeight, in: environment)
        self.kinds = kinds
        self.cutOff = cutOff
    }

    /// The line offset a "…" link stands for.
    static func expandedLine(_ url: URL) -> Int? {
        let text = url.absoluteString
        guard text.hasPrefix(expandLinkPrefix) else { return nil }
        return Int(text.dropFirst(expandLinkPrefix.count))
    }

    /// The line cut to `columns` characters, ending in the "…" marker, or nil when it fits.
    static func cutOff(_ text: AttributedString, columns: Int) -> AttributedString? {
        guard text.characters.count > columns, columns > 2 else { return nil }
        let end = text.characters.index(text.startIndex, offsetBy: columns - 2)
        return AttributedString(text[text.startIndex..<end]) + cutOffMarker
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
