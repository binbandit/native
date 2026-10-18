import CodeThemes
import GitHub
import SwiftUI

/// A run of diff lines as two texts, the gutter (both line numbers and the change marker) and the
/// code, so a hunk lays out as one text each instead of a view per line: what keeps scrolling a
/// pull request with thousands of changed lines smooth. Lines don't wrap, so every line has the
/// same height and line `i` sits at `i × height`.
struct PullRequestDiffBlockText {
    let gutter: AttributedString
    let code: AttributedString
    let kinds: [DiffHunk.Line.Kind]

    /// Longer lines (minified bundles) show their start; the full line is on GitHub.
    static let maximumLineLength = 1_000

    /// - Parameters:
    ///   - highlighted: The hunk's lines as code segments, when highlighting has finished.
    ///   - numberWidth: Digits in the largest line number of the file, so gutters line up.
    init(
        lines: ArraySlice<DiffHunk.Line>, highlighted: [[CodeSegment]]?, colors: DSCodeColors, numberWidth: Int
    ) {
        var gutter = AttributedString()
        var code = AttributedString()
        var kinds: [DiffHunk.Line.Kind] = []
        for index in lines.indices {
            let line = lines[index]
            if !kinds.isEmpty {
                gutter += AttributedString("\n")
                code += AttributedString("\n")
            }
            kinds.append(line.kind)
            gutter += Self.gutter(line, width: numberWidth)
            code += Self.code(line, highlighted: highlighted.flatMap { $0.indices.contains(index) ? $0[index] : nil }, colors: colors)
        }
        self.gutter = gutter
        self.code = code
        self.kinds = kinds
    }

    private static func gutter(_ line: DiffHunk.Line, width: Int) -> AttributedString {
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

    private static func code(_ line: DiffHunk.Line, highlighted: [CodeSegment]?, colors: DSCodeColors) -> AttributedString {
        if line.kind == .noNewline {
            var text = AttributedString(line.text)
            text.foregroundColor = .dsTextTertiary
            return text
        }
        var text = highlighted.map(colors.text) ?? AttributedString(line.text)
        guard text.characters.count > maximumLineLength else { return text }
        let end = text.characters.index(text.startIndex, offsetBy: maximumLineLength)
        text = AttributedString(text[text.startIndex..<end])
        var more = AttributedString("  … \(line.text.count - maximumLineLength) more characters")
        more.foregroundColor = .dsTextTertiary
        return text + more
    }
}
