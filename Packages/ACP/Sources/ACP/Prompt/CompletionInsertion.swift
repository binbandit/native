/// What accepting a completion (a slash command, an `@` mention) does to the draft: the completion
/// replaces what was typed for it, followed by one space, and the caret lands after that space, so
/// typing carries on from there. A space already after the typed text is reused rather than doubled.
public enum CompletionInsertion {
    public static func draft(
        _ draft: String, replacing typed: Range<String.Index>, with completion: String
    ) -> (text: String, cursor: String.Index) {
        var rest = draft[typed.upperBound...]
        if rest.first == " " {
            rest = rest.dropFirst()
        }
        let head = String(draft[..<typed.lowerBound]) + completion + " "
        let text = head + rest
        return (text, text.utf8.index(text.startIndex, offsetBy: head.utf8.count))
    }
}
