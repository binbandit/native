import SwiftUI

/// Markdown inline code in short text such as titles ("Add `maxLength` option"): each backtick span
/// shows in monospace without its backticks, the rest in the surrounding font. A span closes on a
/// run of as many backticks as opened it, as in Markdown, and backticks with no partner stay as
/// written. Only inline code is styled; other Markdown stays literal, since titles aren't Markdown.
public enum DSInlineCode {
    /// `text` with its code spans set in `codeFont`, for a `Text`, which keeps truncating it.
    public static func attributed(_ text: String, codeFont: Font = .dsMono, codeColor: Color? = nil) -> AttributedString
    {
        styled(AttributedString(text), codeFont: codeFont, codeColor: codeColor)
    }

    /// `text` with its code spans set in `codeFont` and their backticks gone, keeping the attributes
    /// it already has, such as the letters a search matched.
    public static func styled(
        _ text: AttributedString, codeFont: Font = .dsMono, codeColor: Color? = nil
    ) -> AttributedString {
        let characters = Array(text.characters)
        func slice(_ start: Int, _ end: Int) -> AttributedString {
            let all = text.characters
            return AttributedString(
                text[all.index(all.startIndex, offsetBy: start)..<all.index(all.startIndex, offsetBy: end)])
        }
        var result = AttributedString()
        // Up to `copied` is in `result`; `index` is where the search for the next span goes on.
        var copied = 0
        var index = 0
        while index < characters.count {
            guard characters[index] == "`" else {
                index += 1
                continue
            }
            let ticks = run(at: index, in: characters)
            guard let close = closingRun(of: ticks, in: characters, from: index + ticks) else {
                // No partner: these backticks are literal.
                index += ticks
                continue
            }
            result += slice(copied, index)
            let span = trimmed(index + ticks..<close, in: characters)
            var code = slice(span.lowerBound, span.upperBound)
            code.font = codeFont
            if let codeColor { code.foregroundColor = codeColor }
            result += code
            index = close + ticks
            copied = index
        }
        result += slice(copied, characters.count)
        return result
    }

    /// `text` without its code spans' backticks, for places that only take a string (a window title).
    public static func plain(_ text: String) -> String {
        String(attributed(text).characters)
    }

    /// How many backticks start at `index`.
    private static func run(at index: Int, in characters: [Character]) -> Int {
        characters[index...].prefix { $0 == "`" }.count
    }

    /// Where the next run of exactly `count` backticks starts.
    private static func closingRun(of count: Int, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            guard characters[index] == "`" else {
                index += 1
                continue
            }
            let length = run(at: index, in: characters)
            if length == count { return index }
            index += length
        }
        return nil
    }

    /// Markdown drops one space each side of a span padded on both, so `` ` `a` ` `` can hold backticks.
    private static func trimmed(_ span: Range<Int>, in characters: [Character]) -> Range<Int> {
        guard span.count > 2, characters[span.lowerBound] == " ", characters[span.upperBound - 1] == " ",
            characters[span].contains(where: { $0 != " " })
        else { return span }
        return span.lowerBound + 1..<span.upperBound - 1
    }
}

/// A line of text with its inline code in monospace (`DSInlineCode`). Style and truncate it like a
/// `Text`; the code spans keep their font.
public struct DSInlineCodeText: View {
    let text: String
    let codeFont: Font
    let codeColor: Color?

    public init(_ text: String, codeFont: Font = .dsMono, codeColor: Color? = nil) {
        self.text = text
        self.codeFont = codeFont
        self.codeColor = codeColor
    }

    public var body: some View {
        Text(DSInlineCode.attributed(text, codeFont: codeFont, codeColor: codeColor))
    }
}

#Preview("Inline code") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSInlineCodeText("#78 Add `maxLength` option to `TextField`")
            DSInlineCodeText("Unpaired ` backtick stays")
            DSInlineCodeText("Double ``code with ` inside`` works")
            DSInlineCodeText("A long title with `inlineCodeThatGoesOnAndOn` that truncates")
                .lineLimit(1)
                .frame(width: 200, alignment: .leading)
        }
        .font(.dsCalloutBook)
    }
}
