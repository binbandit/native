import Testing

@testable import ACP

struct FileMentionQueryTests {
    @Test(arguments: ["@", "@./", "@./do", "@docs/", "@../", "@./.config/"])
    func queryKeepsTheTypedPath(draft: String) throws {
        let query = try #require(FileMentionQuery(draft: draft, cursor: draft.endIndex))
        #expect(query.text == String(draft.dropFirst()))
    }

    @Test func choosingAFolderLeavesTheCaretAfterItsSlash() throws {
        let draft = "Look in @./do next"
        let cursor = try #require(draft.dropFirst(8).firstIndex(of: " "))
        let query = try #require(FileMentionQuery(draft: draft, cursor: cursor))
        let result = query.draft(draft, inserting: "docs/")
        #expect(result.text == "Look in @docs/ next")
        #expect(String(result.text[..<result.cursor]) == "Look in @docs/")
        #expect(FileMentionQuery(draft: result.text, cursor: result.cursor)?.text == "docs/")
    }

    @Test func choosingAFileStillAddsASpace() throws {
        let draft = "@./READ"
        let query = try #require(FileMentionQuery(draft: draft, cursor: draft.endIndex))
        let result = query.draft(draft, inserting: "README.md")
        #expect(result.text == "@README.md ")
        #expect(result.cursor == result.text.endIndex)
    }

    @Test func aQuotedFolderCanContinueWithoutDuplicatingItsClosingQuote() throws {
        let draft = "👋🏽 @./My"
        let query = try #require(FileMentionQuery(draft: draft, cursor: draft.endIndex))
        let folder = query.draft(draft, inserting: "My Docs/")
        #expect(folder.text == "👋🏽 @\"My Docs/\"")
        #expect(String(folder.text[..<folder.cursor]) == "👋🏽 @\"My Docs/")
        let next = try #require(FileMentionQuery(draft: folder.text, cursor: folder.cursor))
        #expect(next.text == "My Docs/")
        let file = next.draft(folder.text, inserting: "My Docs/guide.md")
        #expect(file.text == "👋🏽 @\"My Docs/guide.md\" ")
        #expect(file.cursor == file.text.endIndex)
    }

    @Test(arguments: ["hello@example.com", "@docs/ ", "@\"My Docs/\" "])
    func completedWordsDoNotOpenTheList(draft: String) {
        #expect(FileMentionQuery(draft: draft, cursor: draft.endIndex) == nil)
    }
}
