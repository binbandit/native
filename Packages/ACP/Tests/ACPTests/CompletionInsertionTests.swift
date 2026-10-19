import Testing

@testable import ACP

@Suite struct CompletionInsertionTests {
    /// The draft and what's after the caret once `completion` replaces `typed` (its first occurrence).
    private func accept(_ completion: String, for typed: String, in draft: String) throws -> (String, String) {
        let range = try #require(draft.range(of: typed))
        let (text, cursor) = CompletionInsertion.draft(draft, replacing: range, with: completion)
        return (text, String(text[cursor...]))
    }

    @Test func aCommandLeavesTheCaretAfterItAndASpace() throws {
        let (text, after) = try accept("/review", for: "/rev", in: "/rev")
        #expect(text == "/review ")
        #expect(after.isEmpty)
    }

    @Test func aMentionMidDraftReusesTheSpaceAfterIt() throws {
        let (text, after) = try accept("@src/Button.tsx", for: "@But", in: "see @But and more")
        #expect(text == "see @src/Button.tsx and more")
        #expect(after == "and more")
    }

    @Test func aMentionBeforePunctuationGetsItsOwnSpace() throws {
        let (text, after) = try accept("@README.md", for: "@READ", in: "see @READ, then")
        #expect(text == "see @README.md , then")
        #expect(after == ", then")
    }

    @Test func theCaretIsRightAfterWideCharacters() throws {
        let (text, after) = try accept("@a/b.swift", for: "@b", in: "👋🏽 é @b")
        #expect(text == "👋🏽 é @a/b.swift ")
        #expect(after.isEmpty)
    }
}
