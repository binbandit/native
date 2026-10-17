import Foundation

/// An `@` mention being typed: the word from an `@` at the start of the draft or after whitespace up
/// to the cursor, as in Factory's composer. Its text is what's typed after the `@`.
struct FileMentionQuery: Equatable {
    /// The `@` and what follows it, up to the cursor.
    let range: Range<String.Index>
    let text: String

    init?(draft: String, cursor: String.Index) {
        guard cursor <= draft.endIndex else { return nil }
        let before = draft[..<cursor]
        guard let at = before.lastIndex(of: "@") else { return nil }
        let typed = before[draft.index(after: at)...]
        // A space ends the mention; an `@` inside a word (an email address) doesn't start one.
        guard !typed.contains(where: \.isWhitespace) else { return nil }
        if at > draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
        range = at..<cursor
        text = String(typed)
    }

    /// The draft with the mention replaced by `path`, and where the cursor goes after it.
    func draft(_ draft: String, inserting path: String) -> (text: String, cursor: String.Index) {
        let mention = FileMentions.mention(of: path) + " "
        var text = draft
        text.replaceSubrange(range, with: mention)
        let cursor = text.index(range.lowerBound, offsetBy: mention.count)
        return (text, cursor)
    }
}
