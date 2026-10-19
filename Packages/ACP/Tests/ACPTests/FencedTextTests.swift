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
}
