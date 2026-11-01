import Foundation

/// The incomplete file or command word immediately before a collapsed caret.
public struct TextInputQuery: Equatable, Sendable {
    public enum Kind: Sendable { case file, command }
    public let kind: Kind
    public let text: String
    /// UTF-16 editor range including the trigger, suitable for replacing with a completion.
    public let range: NSRange

    public init?(document: TextInputDocument, selection: NSRange, isComposing: Bool = false) {
        let display = document.displayText
        guard !isComposing, selection.length == 0,
            let selected = TextInputDocument.validRange(selection, in: display)
        else { return nil }
        let caret = selected.lowerBound
        let prefix = display[..<caret]
        guard
            let start = prefix.indices.reversed().first(where: { index in
                guard display[index] == "@" || display[index] == "/" else { return false }
                if index == display.startIndex { return true }
                let previous = display[display.index(before: index)]
                return previous.isWhitespace || previous == "\u{FFFC}"
            })
        else { return nil }
        var typed = display[display.index(after: start)..<caret]
        let quoted = display[start] == "@" && typed.first == "\""
        if quoted { typed = typed.dropFirst() }
        guard !typed.contains("\u{FFFC}"), !typed.contains("\n"), !typed.contains("\r"),
            quoted ? !typed.contains("\"") : !typed.contains(where: \.isWhitespace)
        else { return nil }
        kind = display[start] == "@" ? .file : .command
        text = String(typed)
        range = NSRange(start..<caret, in: display)
    }
}
