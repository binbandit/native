import ACP
import SwiftUI

/// What the user typed, shown as typed: fenced code blocks render as code blocks and `inline code`
/// as code, the way `FencedText` reads them (the composer reads them the same way); nothing else is
/// interpreted, so a `#` or `*` they wrote stays a `#` or `*`.
struct UserMessageText: View {
    let text: String

    var body: some View {
        let packet = PromptQuote.split(text)
        if packet.quotes.contains(where: { $0.comment != nil }) {
            DiffCommentsTranscriptPacket(quotes: packet.quotes, message: packet.message)
        } else if FencedText.containsFence(text) {
            let segments = FencedText.segments(of: text)
            VStack(alignment: .leading, spacing: DS.Space.md) {
                ForEach(segments.indices, id: \.self) { index in
                    switch segments[index] {
                    case .text(let text):
                        InlineCodeText(text: text)
                    case .code(let code, let language, _):
                        TranscriptCodeBlock(code: code, language: language)
                    }
                }
            }
        } else {
            InlineCodeText(text: text)
        }
    }
}

/// Plain text with its inline code spans set as code: monospaced on a faint fill, without the
/// backticks, as replies show them.
private struct InlineCodeText: View {
    let text: String

    var body: some View {
        if text.contains("`") {
            Text(Self.styled(text))
        } else {
            Text(verbatim: text)
        }
    }

    private static func styled(_ text: String) -> AttributedString {
        var styled = AttributedString()
        var cursor = text.startIndex
        for span in FencedText.inlineCode(in: text) {
            styled += AttributedString(text[cursor..<span.lowerBound])
            var code = AttributedString(Self.content(of: text[span]))
            code.inlinePresentationIntent = .code
            code.backgroundColor = .dsFill
            styled += code
            cursor = span.upperBound
        }
        styled += AttributedString(text[cursor...])
        return styled
    }

    /// A span's code: inside the backticks, with line breaks as spaces and one space dropped from
    /// each end when both ends have one, as CommonMark has it.
    private static func content(of span: Substring) -> String {
        let fence = span.prefix { $0 == "`" }.count
        var code = String(span.dropFirst(fence).dropLast(fence)).replacingOccurrences(of: "\n", with: " ")
        if code.count > 2, code.hasPrefix(" "), code.hasSuffix(" "), code.contains(where: { $0 != " " }) {
            code = String(code.dropFirst().dropLast())
        }
        return code
    }
}

#if DEBUG
#Preview("User message - Comment packet and code") {
    DSPreviewPair {
        DiffCommentsPreviewHost { session in
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                UserMessageText(text: session.draft)
                UserMessageText(text: "Keep `lineNumbers` fixed.\n\n```swift\nText(line.text)\n```")
            }.padding(DS.Space.xl).frame(width: 500)
        }
    }
}
#endif
