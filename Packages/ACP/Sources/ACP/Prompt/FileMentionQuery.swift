import Foundation

/// An `@` mention being typed: the word from an `@` at the start of the draft or after whitespace up
/// to the cursor. Its text is what's typed after the `@`.
public struct FileMentionQuery: Equatable, Sendable {
    /// The `@` and what follows it, up to the cursor.
    public let range: Range<String.Index>
    public let text: String

    public init?(draft: String, cursor: String.Index) {
        guard cursor <= draft.endIndex else { return nil }
        let before = draft[..<cursor]
        guard let at = before.lastIndex(of: "@") else { return nil }
        var typed = before[draft.index(after: at)...]
        let isQuoted = typed.first == "\""
        if isQuoted { typed = typed.dropFirst() }
        // A space ends the mention; an `@` inside a word (an email address) doesn't start one.
        guard isQuoted ? !typed.contains("\"") : !typed.contains(where: \.isWhitespace) else { return nil }
        if at > draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
        let end = isQuoted && draft[cursor...].first == "\"" ? draft.index(after: cursor) : cursor
        range = at..<end
        text = String(typed)
    }

    /// The draft with the mention replaced by `path`, and where the cursor goes after it.
    public func draft(_ draft: String, inserting path: String) -> (text: String, cursor: String.Index) {
        let mention = FileMention.mention(of: path)
        guard FileMention.isFolder(path) else {
            return CompletionInsertion.draft(draft, replacing: range, with: mention)
        }
        // A folder stays open for the next path component, including inside a quoted path.
        let head = String(draft[..<range.lowerBound]) + mention
        let text = head + draft[range.upperBound...]
        let caretOffset = head.utf8.count - (mention.hasSuffix("\"") ? 1 : 0)
        return (text, text.utf8.index(text.startIndex, offsetBy: caretOffset))
    }
}
