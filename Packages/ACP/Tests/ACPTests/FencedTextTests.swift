import Testing

@testable import ACP

struct FencedTextTests {
    @Test func plainTextStaysExactlyAsTyped() {
        let text = "# Not a heading\n* not a list\n**not bold** and `inline code`\n"
        #expect(FencedText.segments(of: text) == [.text(text)])
        #expect(!FencedText.containsFence(text))
    }

    @Test func splitsTextAroundABlock() {
        let text = "Why does this fail?\n```swift\nlet x = 1\n  print(x)\n```\nThanks"
        #expect(
            FencedText.segments(of: text) == [
                .text("Why does this fail?"),
                .code("let x = 1\n  print(x)", language: "swift", isClosed: true),
                .text("Thanks"),
            ])
    }

    @Test func twoBlocksAndTildeFences() {
        let text = "a\n~~~\none\n~~~\nb\n````js title=x\ntwo ``` still code\n````"
        #expect(
            FencedText.segments(of: text) == [
                .text("a"),
                .code("one", language: nil, isClosed: true),
                .text("b"),
                .code("two ``` still code", language: "js", isClosed: true),
            ])
    }

    @Test func anUnclosedFenceRunsToTheEnd() {
        let text = "Here:\n```python\nprint('hi')\n\nmore"
        #expect(
            FencedText.segments(of: text) == [
                .text("Here:"),
                .code("print('hi')\n\nmore", language: "python", isClosed: false),
            ])
    }

    @Test func closersMustMatchAndOpenersFollowCommonMark() {
        // A shorter run, the other character, or text after it doesn't close the block.
        let text = "````\n```\n~~~~\n```` not yet\n````"
        #expect(
            FencedText.segments(of: text) == [.code("```\n~~~~\n```` not yet", language: nil, isClosed: true)])
        // Inline code, four spaces of indent, and a backtick in the info string aren't fences.
        for text in ["``not a fence``", "    ```\nx", "``` a`b\nx"] {
            #expect(!FencedText.containsFence(text))
        }
    }

    @Test func indentedFencesDedentTheirCode() {
        let text = "  ```\n  indented\n    deeper\n  ```"
        #expect(FencedText.segments(of: text) == [.code("indented\n  deeper", language: nil, isClosed: true)])
    }

    @Test func blocksLocateTheirFencesAndCode() throws {
        let text = "Look:\n```swift\nlet x = 1\n```\nand\n```\nopen"
        let blocks = FencedText.blocks(in: text)
        #expect(blocks.count == 2)
        let first = try #require(blocks.first)
        #expect(text[first.range] == "```swift\nlet x = 1\n```")
        #expect(text[first.contentRange] == "let x = 1")
        #expect(first.language == "swift" && first.isClosed)
        let last = try #require(blocks.last)
        #expect(text[last.range] == "```\nopen")
        #expect(text[last.contentRange] == "open")
        #expect(!last.isClosed)
        // A block with no code has an empty content range right after its opening line.
        let empty = try #require(FencedText.blocks(in: "```\n```").first)
        #expect(empty.contentRange.isEmpty)
    }

    @Test func inlineCodeFollowsCommonMarkSpans() {
        let text = "Run `swift test` or ``a ` b``, not \\`this`, and `unmatched"
        let spans = FencedText.inlineCode(in: text).map { String(text[$0]) }
        #expect(spans == ["`swift test`", "``a ` b``"])
    }

    @Test func inlineCodeSkipsFencedBlocks() {
        let text = "`one`\n```\n`not inline`\n```\n`two`"
        #expect(FencedText.inlineCode(in: text).map { String(text[$0]) } == ["`one`", "`two`"])
    }
}
