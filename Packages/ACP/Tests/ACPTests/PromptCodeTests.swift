import Testing

@testable import ACP

@Suite struct PromptCodeTests {
    /// `draft` with `|` marking the caret, as the text and the caret's index in it.
    private func caret(_ draft: String) throws -> (String, String.Index) {
        let marker = try #require(draft.firstIndex(of: "|"))
        let offset = draft.utf8.distance(from: draft.startIndex, to: marker)
        let text = draft.replacingOccurrences(of: "|", with: "")
        return (text, text.utf8.index(text.startIndex, offsetBy: offset))
    }

    /// `draft` with `[` and `]` marking the selection.
    private func selection(_ draft: String) throws -> (String, Range<String.Index>) {
        let open = try #require(draft.firstIndex(of: "["))
        let lower = draft.utf8.distance(from: draft.startIndex, to: open)
        let upper = try draft.utf8.distance(from: draft.startIndex, to: #require(draft.firstIndex(of: "]"))) - 1
        let text = draft.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        return (text, text.utf8.index(text.startIndex, offsetBy: lower)..<text.utf8.index(text.startIndex, offsetBy: upper))
    }

    /// An edit's text with its selection marked as in `selection(_:)`, or `|` for a caret.
    private func marked(_ edit: PromptCode.Edit) -> String {
        var text = edit.text
        if edit.selection.isEmpty {
            text.insert("|", at: edit.selection.lowerBound)
        } else {
            text.insert("]", at: edit.selection.upperBound)
            text.insert("[", at: edit.selection.lowerBound)
        }
        return text
    }

    @Test(arguments: [
        ("```|", true),  // just typed: Return starts the code
        ("```swift|\nlet x = 1\n```", true),
        ("```swift\nlet x|\n```", true),
        ("```swift\nlet x\n```|", false),  // past the closing fence, Return sends
        ("|```swift\nlet x\n```", false),
        ("Look:\n```\nunclosed|", true),
        ("```\na\n```\nthen prose|", false),
        ("no code here|", false),
        ("an inline `co|de` span", false),
    ])
    func whetherTheCaretIsInABlock(draft: String, isIn: Bool) throws {
        let (text, cursor) = try caret(draft)
        #expect(PromptCode.isInBlock(cursor, in: text) == isIn)
    }

    @Test func inlineSpansAreCodeButNotBlocks() throws {
        let (inside, cursor) = try caret("an inline `co|de` span")
        #expect(PromptCode.isInCode(cursor, in: inside))
        let (after, end) = try caret("an inline `code`| span")
        #expect(!PromptCode.isInCode(end, in: after))
    }

    @Test func rangesCoverBlocksWithTheirFencesAndInlineSpansWithTheirBackticks() {
        let text = "Run `make`:\n```sh\nmake all\n```\ndone"
        #expect(PromptCode.ranges(in: text).map { String(text[$0]) }.sorted() == ["```sh\nmake all\n```", "`make`"])
    }

    @Test func returnKeepsTheLinesIndentation() throws {
        let (text, cursor) = try caret("```py\ndef f():\n    if x:|\n```")
        #expect(marked(PromptCode.newline(in: text, replacing: cursor..<cursor)) == "```py\ndef f():\n    if x:\n    |\n```")
        let (tabbed, end) = try caret("```go\n\tfmt.Println()|")
        #expect(marked(PromptCode.newline(in: tabbed, replacing: end..<end)) == "```go\n\tfmt.Println()\n\t|")
    }

    @Test func tabIndentsAtTheCaretInTheBlocksOwnUnit() throws {
        let (spaces, cursor) = try caret("```js\nif (a) {\n  b()\n|\n```")
        #expect(marked(PromptCode.indent(in: spaces, selection: cursor..<cursor)) == "```js\nif (a) {\n  b()\n  |\n```")
        let (tabs, end) = try caret("```go\n\tx := 1\n|")
        #expect(marked(PromptCode.indent(in: tabs, selection: end..<end)) == "```go\n\tx := 1\n\t|")
        let (plain, start) = try caret("```\n|")
        #expect(marked(PromptCode.indent(in: plain, selection: start..<start)) == "```\n    |")
    }

    @Test func tabIndentsEverySelectedLineButEmptyOnes() throws {
        let (text, range) = try selection("```\nfo[o\n\nbar\n]baz\n```")
        #expect(marked(PromptCode.indent(in: text, selection: range)) == "```\n[    foo\n\n    bar]\nbaz\n```")
    }

    @Test func shiftTabOutdentsTabsOrUpToAnIndentOfSpaces() throws {
        let (text, range) = try selection("```\n[\tone\n      two\n three]\n```")
        #expect(marked(PromptCode.outdent(in: text, selection: range)) == "```\n[one\n  two\nthree]\n```")
        let (line, cursor) = try caret("```\n    x = |1\n```")
        #expect(marked(PromptCode.outdent(in: line, selection: cursor..<cursor)) == "```\nx = |1\n```")
        let (shallow, near) = try caret("```\n  |x\n```")
        #expect(marked(PromptCode.outdent(in: shallow, selection: near..<near)) == "```\n|x\n```")
    }
}
