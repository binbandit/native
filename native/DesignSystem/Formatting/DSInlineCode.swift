import SwiftUI

/// Markdown inline code in short text such as titles ("Add `maxLength` option"): each backtick span
/// shows in monospace without its backticks, the rest in the surrounding font. A span closes on a
/// run of as many backticks as opened it, as in Markdown, and backticks with no partner stay as
/// written. Only inline code is styled; other Markdown stays literal, since titles aren't Markdown.
public enum DSInlineCode {
    /// `text` with its code spans set in `codeFont`, for a `Text`, which keeps truncating it.
    public static func attributed(_ text: String, codeFont: Font = .dsMono) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(text)
        while let open = rest.firstIndex(of: "`") {
            let ticks = rest[open...].prefix { $0 == "`" }
            let afterOpen = ticks.endIndex
            guard let close = closingRun(of: ticks.count, in: rest[afterOpen...]) else {
                // No partner: these backticks are literal, and the search goes on after them.
                result += AttributedString(rest[..<afterOpen])
                rest = rest[afterOpen...]
                continue
            }
            result += AttributedString(rest[..<open])
            var code = AttributedString(trimmedSpan(rest[afterOpen..<close.lowerBound]))
            code.font = codeFont
            result += code
            rest = rest[close.upperBound...]
        }
        result += AttributedString(rest)
        return result
    }

    /// The next run of exactly `count` backticks.
    private static func closingRun(of count: Int, in text: Substring) -> Range<Substring.Index>? {
        var index = text.startIndex
        while let start = text[index...].firstIndex(of: "`") {
            let run = text[start...].prefix { $0 == "`" }
            if run.count == count { return start..<run.endIndex }
            index = run.endIndex
        }
        return nil
    }

    /// Markdown drops one space each side of a span padded on both, so `` ` `a` ` `` can hold backticks.
    private static func trimmedSpan(_ span: Substring) -> Substring {
        guard span.count > 2, span.first == " ", span.last == " ", span.contains(where: { $0 != " " }) else {
            return span
        }
        return span.dropFirst().dropLast()
    }
}

/// A line of text with its inline code in monospace (`DSInlineCode`). Style and truncate it like a
/// `Text`; the code spans keep their font.
public struct DSInlineCodeText: View {
    let text: String
    let codeFont: Font

    public init(_ text: String, codeFont: Font = .dsMono) {
        self.text = text
        self.codeFont = codeFont
    }

    public var body: some View {
        Text(DSInlineCode.attributed(text, codeFont: codeFont))
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
